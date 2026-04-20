package model

import "time"

type EntitlementStatus string

const (
	StatusFree     EntitlementStatus = "free"
	StatusTrial    EntitlementStatus = "trial"
	StatusPro      EntitlementStatus = "pro"
	StatusPastDue  EntitlementStatus = "past_due"
	StatusCanceled EntitlementStatus = "canceled"
)

type Entitlement struct {
	UserID         string            `json:"user_id"`
	Email          string            `json:"email,omitempty"`
	Provider       string            `json:"provider,omitempty"`
	Status         EntitlementStatus `json:"status"`
	Plan           string            `json:"plan,omitempty"`
	Country        string            `json:"country,omitempty"`
	SubscriptionID string            `json:"subscription_id,omitempty"`
	TrialStartedAt *time.Time        `json:"trial_started_at,omitempty"`
	TrialEndsAt    *time.Time        `json:"trial_ends_at,omitempty"`
	UpdatedAt      time.Time         `json:"updated_at"`
}

type CloudServer struct {
	ID                string    `json:"id"`
	UserID            string    `json:"user_id"`
	Agent             string    `json:"agent"`
	Region            string    `json:"region"`
	Country           string    `json:"country,omitempty"`
	Status            string    `json:"status"`
	DropletID         int64     `json:"droplet_id,omitempty"`
	PublicIPv4        string    `json:"public_ipv4,omitempty"`
	TailscaleHostname string    `json:"tailscale_hostname,omitempty"`
	TailscaleAuthKeyID string   `json:"tailscale_auth_key_id,omitempty"`
	RepoURL           string   `json:"repo_url,omitempty"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

type WebhookEvent struct {
	ID        string    `json:"id"`
	Provider  string    `json:"provider"`
	EventType string    `json:"event_type"`
	UserID    string    `json:"user_id,omitempty"`
	Processed bool      `json:"processed"`
	CreatedAt time.Time `json:"created_at"`
}

type ProvisionRequest struct {
	UserID  string `json:"user_id"`
	Email   string `json:"email,omitempty"`
	Country string `json:"country,omitempty"`
	Agent   string `json:"agent,omitempty"`
	RepoURL string `json:"repo_url,omitempty"`
	ClientIP string `json:"-"`
}

type ProvisionResponse struct {
	ServerID         string `json:"server_id"`
	Status           string `json:"status"`
	Region           string `json:"region"`
	EstimatedSeconds int    `json:"estimated_seconds"`
	Message          string `json:"message"`
}
