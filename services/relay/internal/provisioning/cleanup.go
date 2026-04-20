package provisioning

import (
	"context"
	"log"
	"time"
)

func (p *Provisioner) RunCleanupWorker(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		p.cleanupOnce(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (p *Provisioner) cleanupOnce(ctx context.Context) {
	cutoff := time.Now().UTC().Add(-30 * time.Minute)
	servers, err := p.store.ListStaleCreatingCloudServers(ctx, cutoff)
	if err != nil {
		log.Printf("cleanup: list stale cloud servers failed: %v", err)
		return
	}
	for _, server := range servers {
		if server.DropletID != 0 {
			if err := DeleteDroplet(ctx, p.cfg, server.DropletID); err != nil {
				log.Printf("cleanup: delete droplet server=%s droplet=%d failed: %v", server.ID, server.DropletID, err)
				continue
			}
		}
		_ = p.store.UpdateCloudServer(ctx, server.ID, map[string]any{"status": "failed"})
		_ = p.store.InsertCloudEvent(ctx, server.ID, "failed", "provisioning timed out; stale droplet cleaned up")
	}
}
