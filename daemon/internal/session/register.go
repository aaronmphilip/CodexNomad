package session

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/codexnomad/codexnomad/daemon/internal/config"
	"github.com/codexnomad/codexnomad/daemon/internal/qr"
)

func registerCloudSession(ctx context.Context, cfg config.Config, payload qr.PairingPayload) error {
	if cfg.CloudRegisterURL == "" || cfg.CloudServerID == "" {
		return nil
	}
	body := map[string]any{
		"server_id":         cfg.CloudServerID,
		"status":            "session_ready",
		"daemon_session_id": payload.SessionID,
		"agent":             payload.Agent,
		"mode":              payload.Mode,
		"pairing":           payload,
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, cfg.CloudRegisterURL, bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if cfg.CloudRegisterToken != "" {
		req.Header.Set("X-CodexNomad-Token", cfg.CloudRegisterToken)
		req.Header.Set("Authorization", "Bearer "+cfg.CloudRegisterToken)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("cloud session registration failed: %s", res.Status)
	}
	return nil
}
