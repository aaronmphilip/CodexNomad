package provisioning

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/config"
)

type Droplet struct {
	ID     int64
	Name   string
	IPv4   string
	Region string
}

func CreateDroplet(ctx context.Context, cfg config.Config, name, region, userData string) (Droplet, error) {
	if cfg.DigitalOceanToken == "" {
		return Droplet{}, fmt.Errorf("DIGITALOCEAN_TOKEN is required for cloud provisioning")
	}
	body := map[string]any{
		"name":       name,
		"region":     region,
		"size":       cfg.DigitalOceanSize,
		"image":      cfg.DigitalOceanImage,
		"monitoring": true,
		"tags":       []string{cfg.DigitalOceanTag, "codexnomad-cloud"},
		"user_data":  userData,
	}
	if len(cfg.DigitalOceanSSHKeys) > 0 {
		var keys []any
		for _, key := range cfg.DigitalOceanSSHKeys {
			if id, err := strconv.Atoi(key); err == nil {
				keys = append(keys, id)
			} else {
				keys = append(keys, key)
			}
		}
		body["ssh_keys"] = keys
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.digitalocean.com/v2/droplets", bytes.NewReader(raw))
	if err != nil {
		return Droplet{}, err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.DigitalOceanToken)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 30 * time.Second}
	res, err := client.Do(req)
	if err != nil {
		return Droplet{}, err
	}
	defer res.Body.Close()
	payload, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return Droplet{}, fmt.Errorf("digitalocean droplet create failed: %s: %s", res.Status, strings.TrimSpace(string(payload)))
	}
	var out struct {
		Droplet struct {
			ID       int64  `json:"id"`
			Name     string `json:"name"`
			Networks struct {
				V4 []struct {
					IPAddress string `json:"ip_address"`
					Type      string `json:"type"`
				} `json:"v4"`
			} `json:"networks"`
		} `json:"droplet"`
	}
	if err := json.Unmarshal(payload, &out); err != nil {
		return Droplet{}, err
	}
	d := Droplet{ID: out.Droplet.ID, Name: out.Droplet.Name, Region: region}
	for _, ip := range out.Droplet.Networks.V4 {
		if ip.Type == "public" {
			d.IPv4 = ip.IPAddress
			break
		}
	}
	return d, nil
}

func DeleteDroplet(ctx context.Context, cfg config.Config, dropletID int64) error {
	if dropletID == 0 {
		return nil
	}
	if cfg.DigitalOceanToken == "" {
		return fmt.Errorf("DIGITALOCEAN_TOKEN is required to delete droplets")
	}
	url := fmt.Sprintf("https://api.digitalocean.com/v2/droplets/%d", dropletID)
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.DigitalOceanToken)
	client := &http.Client{Timeout: 20 * time.Second}
	res, err := client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode == http.StatusNotFound || res.StatusCode == http.StatusNoContent {
		return nil
	}
	payload, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("digitalocean droplet delete failed: %s: %s", res.Status, strings.TrimSpace(string(payload)))
	}
	return nil
}
