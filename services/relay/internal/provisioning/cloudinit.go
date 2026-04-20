package provisioning

import (
	"fmt"
	"strings"

	"github.com/codexnomad/codexnomad/services/relay/internal/config"
	"github.com/codexnomad/codexnomad/services/relay/internal/model"
)

func CloudInit(cfg config.Config, req model.ProvisionRequest, server model.CloudServer, tailscaleAuthKey string) string {
	codexInstall := shellLine(cfg.CodeXInstallCommand)
	claudeInstall := shellLine(cfg.ClaudeInstallCommand)
	repoClone := ""
	if req.RepoURL != "" {
		repoClone = fmt.Sprintf("git clone %q /workspace/project || true", req.RepoURL)
	}
	return fmt.Sprintf(`#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl git tar unzip nodejs npm

curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --auth-key=%q --hostname=%q --advertise-tags=%q

mkdir -p /opt/codexnomad /workspace
arch="$(uname -m)"
case "$arch" in
  x86_64) cn_arch="amd64" ;;
  aarch64|arm64) cn_arch="arm64" ;;
  *) cn_arch="amd64" ;;
esac
curl -fsSL "%s/codexnomad_linux_${cn_arch}.tar.gz" -o /tmp/codexnomad.tar.gz
tar -xzf /tmp/codexnomad.tar.gz -C /usr/local/bin codexnomad
chmod 0755 /usr/local/bin/codexnomad

%s
%s
%s

cat >/etc/systemd/system/codexnomad.service <<'UNIT'
[Unit]
Description=Codex Nomad cloud daemon
After=network-online.target tailscaled.service
Wants=network-online.target tailscaled.service

[Service]
Type=simple
Environment=CODEXNOMAD_MODE=cloud
Environment=CODEXNOMAD_RELAY_URL=%s
Environment=CODEXNOMAD_REQUIRE_RELAY=1
Environment=CODEXNOMAD_RELAY_TOKEN=%s
WorkingDirectory=/workspace
ExecStart=/usr/local/bin/codexnomad start
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now codexnomad.service

curl -fsSL -X POST "%s/v1/cloud/nodes/register" \
  -H "Content-Type: application/json" \
  -H "X-CodexNomad-Token: %s" \
  -d '{"server_id":"%s","status":"ready","tailscale_hostname":"%s"}' || true
`, tailscaleAuthKey, server.TailscaleHostname, strings.Join(cfg.TailscaleTags, ","), cfg.ReleaseBaseURL,
		codexInstall, claudeInstall, repoClone, cfg.DaemonRelayURL, cfg.RelaySharedToken,
		cfg.CloudBootstrapURL, cfg.AdminSharedToken, server.ID, server.TailscaleHostname)
}

func shellLine(cmd string) string {
	cmd = strings.TrimSpace(cmd)
	if cmd == "" {
		return ":"
	}
	return cmd
}
