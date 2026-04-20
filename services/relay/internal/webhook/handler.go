package webhook

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/config"
	"github.com/codexnomad/codexnomad/services/relay/internal/model"
	"github.com/codexnomad/codexnomad/services/relay/internal/provisioning"
	"github.com/codexnomad/codexnomad/services/relay/internal/supabase"
)

type Handler struct {
	cfg   config.Config
	store *supabase.Client
	prov  *provisioning.Provisioner
}

func New(cfg config.Config, store *supabase.Client, prov *provisioning.Provisioner) *Handler {
	return &Handler{cfg: cfg, store: store, prov: prov}
}

func (h *Handler) Polar(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 2<<20))
	if err != nil {
		http.Error(w, "read failed", http.StatusBadRequest)
		return
	}
	if err := verifyPolarStandardWebhook(raw, r.Header.Get("webhook-id"), r.Header.Get("webhook-timestamp"), r.Header.Get("webhook-signature"), h.cfg.PolarWebhookSecret); err != nil {
		http.Error(w, "invalid signature", http.StatusUnauthorized)
		return
	}
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	eventType := stringField(payload, "type", "event")
	userID, email, country := extractIdentity(payload)
	status := polarStatus(eventType, payload)
	subID := nestedString(payload, "data", "id")
	if userID == "" {
		userID = nestedString(payload, "data", "customer", "external_id")
	}
	if userID == "" {
		http.Error(w, "missing user id in metadata", http.StatusBadRequest)
		return
	}
	ent := model.Entitlement{
		UserID:         userID,
		Email:          email,
		Provider:       "polar",
		Status:         status,
		Plan:           "pro_global",
		Country:        country,
		SubscriptionID: subID,
		UpdatedAt:      time.Now().UTC(),
	}
	_ = h.store.InsertWebhookEvent(r.Context(), model.WebhookEvent{
		ID:        firstNonEmpty(r.Header.Get("webhook-id"), "polar_"+time.Now().UTC().Format("20060102150405.000000000")),
		Provider:  "polar",
		EventType: eventType,
		UserID:    userID,
		Processed: true,
		CreatedAt: time.Now().UTC(),
	})
	if err := h.store.UpsertEntitlement(r.Context(), ent); err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	if status == model.StatusPro || status == model.StatusTrial {
		go h.provisionAfterWebhook(userID, email, country, "codex")
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) Razorpay(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 2<<20))
	if err != nil {
		http.Error(w, "read failed", http.StatusBadRequest)
		return
	}
	if !verifyRazorpay(raw, r.Header.Get("X-Razorpay-Signature"), h.cfg.RazorpayWebhookSecret) {
		http.Error(w, "invalid signature", http.StatusUnauthorized)
		return
	}
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	eventType := stringField(payload, "event", "type")
	userID, email, country := extractIdentity(payload)
	if country == "" {
		country = "IN"
	}
	subID := nestedString(payload, "payload", "subscription", "entity", "id")
	if userID == "" {
		http.Error(w, "missing user id in subscription notes", http.StatusBadRequest)
		return
	}
	status := razorpayStatus(eventType)
	ent := model.Entitlement{
		UserID:         userID,
		Email:          email,
		Provider:       "razorpay",
		Status:         status,
		Plan:           "pro_india",
		Country:        country,
		SubscriptionID: subID,
		UpdatedAt:      time.Now().UTC(),
	}
	_ = h.store.InsertWebhookEvent(r.Context(), model.WebhookEvent{
		ID:        firstNonEmpty(r.Header.Get("x-razorpay-event-id"), "razorpay_"+time.Now().UTC().Format("20060102150405.000000000")),
		Provider:  "razorpay",
		EventType: eventType,
		UserID:    userID,
		Processed: true,
		CreatedAt: time.Now().UTC(),
	})
	if err := h.store.UpsertEntitlement(r.Context(), ent); err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	if status == model.StatusPro {
		go h.provisionAfterWebhook(userID, email, country, "codex")
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) provisionAfterWebhook(userID, email, country, agent string) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	_, _ = h.prov.StartCloudSession(ctx, model.ProvisionRequest{
		UserID:  userID,
		Email:   email,
		Country: country,
		Agent:   agent,
	})
}

func polarStatus(eventType string, payload map[string]any) model.EntitlementStatus {
	eventType = strings.ToLower(eventType)
	switch eventType {
	case "subscription.active", "subscription.created", "subscription.uncanceled", "order.paid":
		return model.StatusPro
	case "subscription.past_due":
		return model.StatusPastDue
	case "subscription.canceled", "subscription.revoked":
		return model.StatusCanceled
	default:
		status := strings.ToLower(nestedString(payload, "data", "status"))
		if status == "active" {
			return model.StatusPro
		}
		return model.StatusFree
	}
}

func razorpayStatus(eventType string) model.EntitlementStatus {
	switch strings.ToLower(eventType) {
	case "subscription.activated", "subscription.charged", "subscription.authenticated":
		return model.StatusPro
	case "subscription.paused", "subscription.pending":
		return model.StatusPastDue
	case "subscription.cancelled", "subscription.completed", "subscription.halted":
		return model.StatusCanceled
	default:
		return model.StatusFree
	}
}

func extractIdentity(payload map[string]any) (userID, email, country string) {
	paths := [][]string{
		{"data", "metadata"},
		{"data", "customer", "metadata"},
		{"payload", "subscription", "entity", "notes"},
		{"payload", "payment", "entity", "notes"},
		{"metadata"},
	}
	for _, p := range paths {
		if m, ok := nestedMap(payload, p...); ok {
			userID = firstNonEmpty(userID, stringAny(m["user_id"]), stringAny(m["supabase_user_id"]), stringAny(m["external_id"]))
			email = firstNonEmpty(email, stringAny(m["email"]))
			country = firstNonEmpty(country, stringAny(m["country"]))
		}
	}
	email = firstNonEmpty(email, nestedString(payload, "data", "customer", "email"), nestedString(payload, "payload", "payment", "entity", "email"))
	return
}

func stringField(m map[string]any, keys ...string) string {
	for _, key := range keys {
		if v := stringAny(m[key]); v != "" {
			return v
		}
	}
	return ""
}

func nestedString(m map[string]any, path ...string) string {
	cur := any(m)
	for _, p := range path {
		next, ok := cur.(map[string]any)
		if !ok {
			return ""
		}
		cur = next[p]
	}
	return stringAny(cur)
}

func nestedMap(m map[string]any, path ...string) (map[string]any, bool) {
	cur := any(m)
	for _, p := range path {
		next, ok := cur.(map[string]any)
		if !ok {
			return nil, false
		}
		cur = next[p]
	}
	out, ok := cur.(map[string]any)
	return out, ok
}

func stringAny(v any) string {
	switch x := v.(type) {
	case string:
		return strings.TrimSpace(x)
	case fmt.Stringer:
		return strings.TrimSpace(x.String())
	default:
		return ""
	}
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}
