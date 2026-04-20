package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/model"
)

type Client struct {
	BaseURL string
	Key     string
	HTTP    *http.Client
}

func New(baseURL, key string) *Client {
	return &Client{
		BaseURL: baseURL,
		Key:     key,
		HTTP:    &http.Client{Timeout: 20 * time.Second},
	}
}

func (c *Client) Enabled() bool {
	return c.BaseURL != "" && c.Key != ""
}

func (c *Client) UpsertEntitlement(ctx context.Context, e model.Entitlement) error {
	if !c.Enabled() {
		return nil
	}
	e.UpdatedAt = time.Now().UTC()
	return c.do(ctx, http.MethodPost, "/rest/v1/subscriptions?on_conflict=user_id", e, nil, "resolution=merge-duplicates")
}

func (c *Client) GetEntitlement(ctx context.Context, userID string) (model.Entitlement, bool, error) {
	if !c.Enabled() {
		return model.Entitlement{}, false, nil
	}
	var rows []model.Entitlement
	path := "/rest/v1/subscriptions?select=*&user_id=eq." + url.QueryEscape(userID) + "&limit=1"
	if err := c.do(ctx, http.MethodGet, path, nil, &rows, ""); err != nil {
		return model.Entitlement{}, false, err
	}
	if len(rows) == 0 {
		return model.Entitlement{}, false, nil
	}
	return rows[0], true, nil
}

func (c *Client) InsertCloudServer(ctx context.Context, server model.CloudServer) error {
	if !c.Enabled() {
		return nil
	}
	return c.do(ctx, http.MethodPost, "/rest/v1/cloud_servers", server, nil, "")
}

func (c *Client) UpdateCloudServer(ctx context.Context, id string, fields map[string]any) error {
	if !c.Enabled() {
		return nil
	}
	fields["updated_at"] = time.Now().UTC()
	return c.do(ctx, http.MethodPatch, "/rest/v1/cloud_servers?id=eq."+url.QueryEscape(id), fields, nil, "")
}

func (c *Client) InsertCloudEvent(ctx context.Context, serverID, eventType, message string) error {
	if !c.Enabled() {
		return nil
	}
	body := map[string]any{
		"server_id":  serverID,
		"event_type": eventType,
		"message":    message,
	}
	return c.do(ctx, http.MethodPost, "/rest/v1/cloud_events", body, nil, "")
}

func (c *Client) FindActiveCloudServer(ctx context.Context, userID string) (model.CloudServer, bool, error) {
	if !c.Enabled() {
		return model.CloudServer{}, false, nil
	}
	var rows []model.CloudServer
	path := "/rest/v1/cloud_servers?select=*&user_id=eq." + url.QueryEscape(userID) + "&status=in.(creating,ready)&order=created_at.desc&limit=1"
	if err := c.do(ctx, http.MethodGet, path, nil, &rows, ""); err != nil {
		return model.CloudServer{}, false, err
	}
	if len(rows) == 0 {
		return model.CloudServer{}, false, nil
	}
	return rows[0], true, nil
}

func (c *Client) GetCloudServer(ctx context.Context, id string) (model.CloudServer, bool, error) {
	if !c.Enabled() {
		return model.CloudServer{}, false, nil
	}
	var rows []model.CloudServer
	path := "/rest/v1/cloud_servers?select=*&id=eq." + url.QueryEscape(id) + "&limit=1"
	if err := c.do(ctx, http.MethodGet, path, nil, &rows, ""); err != nil {
		return model.CloudServer{}, false, err
	}
	if len(rows) == 0 {
		return model.CloudServer{}, false, nil
	}
	return rows[0], true, nil
}

func (c *Client) ListStaleCreatingCloudServers(ctx context.Context, cutoff time.Time) ([]model.CloudServer, error) {
	if !c.Enabled() {
		return nil, nil
	}
	var rows []model.CloudServer
	path := "/rest/v1/cloud_servers?select=*&status=eq.creating&created_at=lt." + url.QueryEscape(cutoff.UTC().Format(time.RFC3339)) + "&limit=25"
	if err := c.do(ctx, http.MethodGet, path, nil, &rows, ""); err != nil {
		return nil, err
	}
	return rows, nil
}

func (c *Client) InsertWebhookEvent(ctx context.Context, ev model.WebhookEvent) error {
	if !c.Enabled() {
		return nil
	}
	return c.do(ctx, http.MethodPost, "/rest/v1/webhook_events", ev, nil, "")
}

func (c *Client) do(ctx context.Context, method, path string, body any, out any, prefer string) error {
	if !c.Enabled() {
		return nil
	}
	var rdr io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return err
		}
		rdr = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.BaseURL+path, rdr)
	if err != nil {
		return err
	}
	req.Header.Set("apikey", c.Key)
	req.Header.Set("Authorization", "Bearer "+c.Key)
	req.Header.Set("Content-Type", "application/json")
	if prefer != "" {
		req.Header.Set("Prefer", prefer)
	}
	res, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("supabase %s %s failed: %s: %s", method, path, res.Status, string(raw))
	}
	if out != nil && len(raw) > 0 {
		if err := json.Unmarshal(raw, out); err != nil {
			return err
		}
	}
	return nil
}

func (c *Client) RequireEnabled() error {
	if !c.Enabled() {
		return errors.New("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
	}
	return nil
}
