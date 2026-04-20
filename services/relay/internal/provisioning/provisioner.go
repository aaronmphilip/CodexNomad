package provisioning

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"strings"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/config"
	"github.com/codexnomad/codexnomad/services/relay/internal/model"
	"github.com/codexnomad/codexnomad/services/relay/internal/supabase"
)

type Provisioner struct {
	cfg   config.Config
	store *supabase.Client
}

func New(cfg config.Config, store *supabase.Client) *Provisioner {
	return &Provisioner{cfg: cfg, store: store}
}

func (p *Provisioner) StartCloudSession(ctx context.Context, req model.ProvisionRequest) (model.ProvisionResponse, error) {
	if req.UserID == "" {
		return model.ProvisionResponse{}, fmt.Errorf("user_id is required")
	}
	if req.Agent == "" {
		req.Agent = "codex"
	}
	if req.Agent != "codex" && req.Agent != "claude" {
		return model.ProvisionResponse{}, fmt.Errorf("agent must be codex or claude")
	}

	if existing, ok, err := p.store.FindActiveCloudServer(ctx, req.UserID); err != nil {
		return model.ProvisionResponse{}, err
	} else if ok {
		return model.ProvisionResponse{
			ServerID:         existing.ID,
			Status:           existing.Status,
			Region:           existing.Region,
			EstimatedSeconds: 15,
			Message:          "Cloud runner already exists.",
		}, nil
	}

	now := time.Now().UTC()
	ent, ok, err := p.store.GetEntitlement(ctx, req.UserID)
	if err != nil {
		return model.ProvisionResponse{}, err
	}
	if !ok || ent.Status == model.StatusFree || ent.Status == "" {
		start := now
		end := now.Add(p.cfg.TrialDuration())
		ent = model.Entitlement{
			UserID:         req.UserID,
			Email:          req.Email,
			Provider:       "trial",
			Status:         model.StatusTrial,
			Plan:           "pro_trial",
			Country:        req.Country,
			TrialStartedAt: &start,
			TrialEndsAt:    &end,
			UpdatedAt:      now,
		}
		if err := p.store.UpsertEntitlement(ctx, ent); err != nil {
			return model.ProvisionResponse{}, err
		}
	}
	if ent.Status == model.StatusCanceled || ent.Status == model.StatusPastDue {
		return model.ProvisionResponse{}, fmt.Errorf("cloud access is disabled for subscription status %s", ent.Status)
	}
	if ent.Status == model.StatusTrial && ent.TrialEndsAt != nil && now.After(*ent.TrialEndsAt) {
		return model.ProvisionResponse{}, fmt.Errorf("trial expired; upgrade to continue cloud sessions")
	}

	region := ChooseRegion(req.Country, req.ClientIP)
	serverID := "srv_" + randomID()
	host := "cn-" + short(req.UserID) + "-" + short(serverID)
	server := model.CloudServer{
		ID:        serverID,
		UserID:    req.UserID,
		Agent:     req.Agent,
		Region:    region,
		Country:   strings.ToUpper(req.Country),
		Status:    "creating",
		RepoURL:   req.RepoURL,
		TailscaleHostname: host,
		CreatedAt: now,
		UpdatedAt: now,
	}

	tsKey, err := CreateTailscaleAuthKey(ctx, p.cfg, "Codex Nomad "+serverID)
	if err != nil {
		return model.ProvisionResponse{}, err
	}
	server.TailscaleAuthKeyID = tsKey.ID
	userData := CloudInit(p.cfg, req, server, tsKey.Key)
	droplet, err := CreateDroplet(ctx, p.cfg, host, region, userData)
	if err != nil {
		return model.ProvisionResponse{}, err
	}
	server.DropletID = droplet.ID
	server.PublicIPv4 = droplet.IPv4
	if err := p.store.InsertCloudServer(ctx, server); err != nil {
		return model.ProvisionResponse{}, err
	}

	return model.ProvisionResponse{
		ServerID:         server.ID,
		Status:           server.Status,
		Region:           region,
		EstimatedSeconds: 45,
		Message:          "Building your cloud server.",
	}, nil
}

func randomID() string {
	var raw [12]byte
	_, _ = rand.Read(raw[:])
	return base64.RawURLEncoding.EncodeToString(raw[:])
}

func short(s string) string {
	s = strings.ToLower(strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' {
			return r
		}
		return '-'
	}, s))
	if len(s) > 10 {
		return s[:10]
	}
	return s
}
