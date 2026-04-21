package config

import (
	"errors"
	"os"
	"strings"
	"time"
)

type Config struct {
	Port string

	PublicBaseURL     string
	RelaySharedToken  string
	RelayTicketSecret string
	RelayDebugFrames  bool
	RelayLeakMarkers  []string
	AppSharedToken    string
	AdminSharedToken  string

	SupabaseURL            string
	SupabaseServiceRoleKey string
	SupabaseJWTSecret      string

	DigitalOceanToken   string
	DigitalOceanImage   string
	DigitalOceanSize    string
	DigitalOceanSSHKeys []string
	DigitalOceanTag     string

	TailscaleTailnet string
	TailscaleAPIKey  string
	TailscaleTags    []string

	ReleaseBaseURL       string
	DaemonRelayURL       string
	CloudBootstrapURL    string
	CodeXInstallCommand  string
	ClaudeInstallCommand string

	PolarWebhookSecret    string
	RazorpayWebhookSecret string
	PolarCheckoutURL      string
	RazorpayCheckoutURL   string

	DefaultTrialDays int
}

func Load() (Config, error) {
	cfg := Config{
		Port:                   env("PORT", "8080"),
		PublicBaseURL:          strings.TrimRight(env("PUBLIC_BASE_URL", "http://localhost:8080"), "/"),
		RelaySharedToken:       os.Getenv("RELAY_SHARED_TOKEN"),
		RelayTicketSecret:      os.Getenv("RELAY_TICKET_SECRET"),
		RelayDebugFrames:       envBool("CODEXNOMAD_RELAY_DEBUG_FRAMES"),
		RelayLeakMarkers:       csv(os.Getenv("CODEXNOMAD_RELAY_LEAK_MARKERS")),
		AppSharedToken:         os.Getenv("APP_SHARED_TOKEN"),
		AdminSharedToken:       os.Getenv("ADMIN_SHARED_TOKEN"),
		SupabaseURL:            strings.TrimRight(os.Getenv("SUPABASE_URL"), "/"),
		SupabaseServiceRoleKey: os.Getenv("SUPABASE_SERVICE_ROLE_KEY"),
		SupabaseJWTSecret:      os.Getenv("SUPABASE_JWT_SECRET"),
		DigitalOceanToken:      os.Getenv("DIGITALOCEAN_TOKEN"),
		DigitalOceanImage:      env("DIGITALOCEAN_IMAGE", "ubuntu-24-04-x64"),
		DigitalOceanSize:       env("DIGITALOCEAN_SIZE", "s-1vcpu-2gb"),
		DigitalOceanSSHKeys:    csv(os.Getenv("DIGITALOCEAN_SSH_KEYS")),
		DigitalOceanTag:        env("DIGITALOCEAN_TAG", "codexnomad"),
		TailscaleTailnet:       os.Getenv("TAILSCALE_TAILNET"),
		TailscaleAPIKey:        os.Getenv("TAILSCALE_API_KEY"),
		TailscaleTags:          csv(env("TAILSCALE_TAGS", "tag:codexnomad-cloud")),
		ReleaseBaseURL:         strings.TrimRight(env("CODEXNOMAD_RELEASE_BASE", "https://codexnomad.pro/releases/latest"), "/"),
		DaemonRelayURL:         env("CODEXNOMAD_RELAY_URL", "wss://relay.codexnomad.pro/v1/relay"),
		CloudBootstrapURL:      strings.TrimRight(env("CODEXNOMAD_CLOUD_BOOTSTRAP_URL", env("PUBLIC_BASE_URL", "http://localhost:8080")), "/"),
		CodeXInstallCommand:    os.Getenv("CODEX_INSTALL_CMD"),
		ClaudeInstallCommand:   os.Getenv("CLAUDE_INSTALL_CMD"),
		PolarWebhookSecret:     os.Getenv("POLAR_WEBHOOK_SECRET"),
		RazorpayWebhookSecret:  os.Getenv("RAZORPAY_WEBHOOK_SECRET"),
		PolarCheckoutURL:       os.Getenv("POLAR_CHECKOUT_URL"),
		RazorpayCheckoutURL:    os.Getenv("RAZORPAY_CHECKOUT_URL"),
		DefaultTrialDays:       14,
	}
	if cfg.Port == "" {
		return Config{}, errors.New("PORT is empty")
	}
	return cfg, nil
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func csv(raw string) []string {
	var out []string
	for _, part := range strings.Split(raw, ",") {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func envBool(key string) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	return v == "1" || v == "true" || v == "yes" || v == "on"
}

func (c Config) TrialDuration() time.Duration {
	return time.Duration(c.DefaultTrialDays) * 24 * time.Hour
}
