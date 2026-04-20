package provisioning

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/config"
)

type TailscaleKey struct {
	ID  string
	Key string
}

func CreateTailscaleAuthKey(ctx context.Context, cfg config.Config, description string) (TailscaleKey, error) {
	if cfg.TailscaleTailnet == "" || cfg.TailscaleAPIKey == "" {
		return TailscaleKey{}, fmt.Errorf("TAILSCALE_TAILNET and TAILSCALE_API_KEY are required for cloud provisioning")
	}
	body := map[string]any{
		"capabilities": map[string]any{
			"devices": map[string]any{
				"create": map[string]any{
					"reusable":      false,
					"ephemeral":     false,
					"preauthorized": true,
					"tags":          cfg.TailscaleTags,
				},
			},
		},
		"expirySeconds": 3600,
		"description":   description,
	}
	raw, _ := json.Marshal(body)
	url := "https://api.tailscale.com/api/v2/tailnet/" + cfg.TailscaleTailnet + "/keys"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(raw))
	if err != nil {
		return TailscaleKey{}, err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.TailscaleAPIKey)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 20 * time.Second}
	res, err := client.Do(req)
	if err != nil {
		return TailscaleKey{}, err
	}
	defer res.Body.Close()
	payload, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return TailscaleKey{}, fmt.Errorf("tailscale key create failed: %s: %s", res.Status, strings.TrimSpace(string(payload)))
	}
	var out struct {
		ID  string `json:"id"`
		Key string `json:"key"`
	}
	if err := json.Unmarshal(payload, &out); err != nil {
		return TailscaleKey{}, err
	}
	if out.Key == "" {
		return TailscaleKey{}, fmt.Errorf("tailscale did not return an auth key")
	}
	return TailscaleKey{ID: out.ID, Key: out.Key}, nil
}
