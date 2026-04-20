package httpapi

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/auth"
	"github.com/codexnomad/codexnomad/services/relay/internal/config"
	"github.com/codexnomad/codexnomad/services/relay/internal/model"
	"github.com/codexnomad/codexnomad/services/relay/internal/provisioning"
	"github.com/codexnomad/codexnomad/services/relay/internal/ratelimit"
	"github.com/codexnomad/codexnomad/services/relay/internal/supabase"
	"github.com/codexnomad/codexnomad/services/relay/internal/webhook"
	"github.com/codexnomad/codexnomad/services/relay/internal/ws"
)

type Server struct {
	cfg     config.Config
	hub     *ws.Hub
	store   *supabase.Client
	prov    *provisioning.Provisioner
	hooks   *webhook.Handler
	limiter *ratelimit.Limiter
}

func New(cfg config.Config, hub *ws.Hub, store *supabase.Client, prov *provisioning.Provisioner, hooks *webhook.Handler) *Server {
	return &Server{cfg: cfg, hub: hub, store: store, prov: prov, hooks: hooks, limiter: ratelimit.New(240)}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /v1/relay", s.relay)
	mux.HandleFunc("GET /v1/pricing", s.pricing)
	mux.HandleFunc("POST /v1/billing/checkout", s.billingCheckout)
	mux.HandleFunc("POST /v1/relay/tickets", s.createRelayTicket)
	mux.HandleFunc("POST /v1/cloud/sessions/start", s.startCloudSession)
	mux.HandleFunc("GET /v1/cloud/sessions/{server_id}", s.getCloudSession)
	mux.HandleFunc("POST /v1/cloud/nodes/register", s.registerCloudNode)
	mux.HandleFunc("POST /webhooks/polar", s.hooks.Polar)
	mux.HandleFunc("POST /webhooks/razorpay", s.hooks.Razorpay)
	return s.securityHeaders(mux)
}

func (s *Server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		if !s.limiter.Allow(r) {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":   true,
		"time": time.Now().UTC(),
	})
}

func (s *Server) relay(w http.ResponseWriter, r *http.Request) {
	if s.cfg.RelayTicketSecret != "" {
		raw := firstNonEmpty(r.URL.Query().Get("ticket"), r.Header.Get("X-CodexNomad-Relay-Ticket"), auth.BearerToken(r.Header.Get("Authorization")))
		if _, err := auth.VerifyRelayTicket(raw, s.cfg.RelayTicketSecret); err != nil && !auth.CheckSharedToken(r, s.cfg.RelaySharedToken) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
	} else if s.cfg.RelaySharedToken != "" && !auth.CheckSharedToken(r, s.cfg.RelaySharedToken) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	s.hub.Handle(w, r)
}

func (s *Server) createRelayTicket(w http.ResponseWriter, r *http.Request) {
	userID, _, ok := s.authenticateApp(r)
	if !ok && !auth.CheckSharedToken(r, s.cfg.AdminSharedToken) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var body struct {
		SessionID  string `json:"session_id"`
		UserID     string `json:"user_id"`
		Role       string `json:"role"`
		TTLSeconds int64  `json:"ttl_seconds"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&body); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if body.SessionID == "" || body.Role == "" {
		http.Error(w, "session_id and role are required", http.StatusBadRequest)
		return
	}
	if body.UserID == "" {
		body.UserID = userID
	}
	if body.TTLSeconds <= 0 || body.TTLSeconds > 3600 {
		body.TTLSeconds = 600
	}
	ticket, err := auth.SignRelayTicket(auth.RelayTicket{
		SessionID: body.SessionID,
		UserID:    body.UserID,
		Role:      body.Role,
		ExpiresAt: time.Now().UTC().Add(time.Duration(body.TTLSeconds) * time.Second).Unix(),
	}, s.cfg.RelayTicketSecret)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"ticket":     ticket,
		"expires_in": body.TTLSeconds,
	})
}

func (s *Server) pricing(w http.ResponseWriter, r *http.Request) {
	country := strings.ToUpper(firstNonEmpty(r.URL.Query().Get("country"), countryFromRequest(r)))
	if country == "IN" {
		writeJSON(w, http.StatusOK, map[string]any{
			"country":    country,
			"provider":   "razorpay",
			"price":      "INR 699/mo",
			"trial_days": 14,
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"country":    firstNonEmpty(country, "US"),
		"provider":   "polar",
		"price":      "$12/mo",
		"trial_days": 14,
	})
}

func (s *Server) billingCheckout(w http.ResponseWriter, r *http.Request) {
	userID, email, ok := s.authenticateApp(r)
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var req model.BillingCheckoutRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if userID != "" {
		req.UserID = userID
	}
	if email != "" {
		req.Email = email
	}
	if req.Country == "" {
		req.Country = countryFromRequest(r)
	}
	if strings.ToUpper(req.Country) == "IN" {
		if s.cfg.RazorpayCheckoutURL == "" {
			http.Error(w, "RAZORPAY_CHECKOUT_URL is not configured", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusOK, model.BillingCheckoutResponse{Provider: "razorpay", URL: s.cfg.RazorpayCheckoutURL})
		return
	}
	if s.cfg.PolarCheckoutURL == "" {
		http.Error(w, "POLAR_CHECKOUT_URL is not configured", http.StatusServiceUnavailable)
		return
	}
	writeJSON(w, http.StatusOK, model.BillingCheckoutResponse{Provider: "polar", URL: s.cfg.PolarCheckoutURL})
}

func (s *Server) startCloudSession(w http.ResponseWriter, r *http.Request) {
	userID, email, ok := s.authenticateApp(r)
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var req model.ProvisionRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if userID != "" {
		req.UserID = userID
	}
	if email != "" {
		req.Email = email
	}
	req.ClientIP = ratelimit.ClientIP(r)
	if req.Country == "" {
		req.Country = countryFromRequest(r)
	}
	res, err := s.prov.StartCloudSession(r.Context(), req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, http.StatusAccepted, res)
}

func (s *Server) getCloudSession(w http.ResponseWriter, r *http.Request) {
	userID, _, ok := s.authenticateApp(r)
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	serverID := r.PathValue("server_id")
	if serverID == "" {
		http.Error(w, "server_id is required", http.StatusBadRequest)
		return
	}
	server, ok, err := s.store.GetCloudServer(r.Context(), serverID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	if !ok {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	if userID != "" && server.UserID != userID {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	writeJSON(w, http.StatusOK, server)
}

func (s *Server) registerCloudNode(w http.ResponseWriter, r *http.Request) {
	if !auth.CheckSharedToken(r, s.cfg.AdminSharedToken) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var body struct {
		ServerID          string `json:"server_id"`
		Status            string `json:"status"`
		TailscaleHostname string `json:"tailscale_hostname"`
		DaemonSessionID   string `json:"daemon_session_id"`
		Pairing           any    `json:"pairing"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&body); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if body.ServerID == "" {
		http.Error(w, "server_id is required", http.StatusBadRequest)
		return
	}
	status := firstNonEmpty(body.Status, "ready")
	if status == "session_ready" {
		status = "ready"
	}
	fields := map[string]any{"status": status}
	if body.TailscaleHostname != "" {
		fields["tailscale_hostname"] = body.TailscaleHostname
	}
	if body.DaemonSessionID != "" {
		fields["daemon_session_id"] = body.DaemonSessionID
	}
	if body.Pairing != nil {
		fields["pairing_payload"] = body.Pairing
	}
	if err := s.store.UpdateCloudServer(r.Context(), body.ServerID, fields); err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	_ = s.store.InsertCloudEvent(r.Context(), body.ServerID, status, "cloud node updated")
	w.WriteHeader(http.StatusNoContent)
}

func countryFromRequest(r *http.Request) string {
	for _, key := range []string{"CF-IPCountry", "X-Vercel-IP-Country", "X-Country-Code", "Fly-Client-Country"} {
		if v := strings.TrimSpace(r.Header.Get(key)); v != "" && strings.ToUpper(v) != "XX" {
			return strings.ToUpper(v)
		}
	}
	return ""
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

func (s *Server) authenticateApp(r *http.Request) (userID, email string, ok bool) {
	token := auth.BearerToken(r.Header.Get("Authorization"))
	if token != "" && s.cfg.SupabaseJWTSecret != "" {
		claims, err := auth.VerifySupabaseJWT(token, s.cfg.SupabaseJWTSecret)
		if err == nil {
			return claims.Subject, claims.Email, true
		}
	}
	if auth.CheckSharedToken(r, s.cfg.AppSharedToken) {
		return "", "", true
	}
	return "", "", false
}
