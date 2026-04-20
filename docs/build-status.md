# Codex Nomad Build Status

## Product

Codex Nomad is a premium Android remote-control app for Codex and Claude Code.

The core promise:

- Free tier: control a Codex or Claude session running on the user's laptop or PC.
- Pro tier: run sessions on an automatically provisioned cloud machine so the laptop can be off.
- Relay and backend must not see plaintext code, prompts, terminal output, diffs, or file contents.

## Built So Far

Daemon foundation:

- `codexnomad codex`
- `codexnomad claude`
- `codexnomad install`
- `codexnomad start`
- `codexnomad status`
- `codexnomad stop`
- `codexnomad logs`

Security/session layer:

- Per-session X25519 keypair.
- NaCl/libsodium-compatible encrypted envelopes.
- QR pairing payload with session id, relay URL, agent, mode, public key, creation time, and expiry.
- Relay contract where relay sees session id and ciphertext only.

Runtime:

- Codex/Claude subprocess wrapper.
- Headless `codexnomad cloud-worker` for cloud droplets.
- Cloud worker pairing metadata registration.
- Unix PTY support.
- Windows stdin/stdout fallback.
- Terminal output streaming.
- Mobile command handling for stdin, interrupt, approve, reject, file list, file read, file write, and ping.

Files:

- Git-aware changed-file snapshot.
- Safe relative-path read/write guard.
- Large-file read limit.

Service/install:

- Linux systemd user service.
- macOS launchd agent.
- Windows scheduled-task autostart fallback.
- Hosted installer script ready for `curl -fsSL https://codexnomad.pro/install | sh`.

Docs:

- Daemon usage README.
- Flutter/relay integration contract.
- Happy Coder license preservation note.

Backend:

- Go WebSocket relay.
- Short-lived signed relay tickets.
- Pricing endpoint.
- Billing checkout URL endpoint.
- Supabase auth/trial metadata client.
- Supabase JWT verification scaffold.
- DigitalOcean droplet provisioner.
- Tailscale one-time auth key creation.
- Polar/Razorpay webhook handlers.
- Cloud session state polling.
- Stale droplet cleanup worker.
- Dockerfile and Docker Compose.

## Verified

Using a local Go toolchain:

- `go mod tidy`
- `go build ./cmd/daemon`
- `go test ./...`
- `bin/codexnomad.exe status`

## Not Built Yet

- Flutter Android app.
- Dynamic Polar checkout creation using Polar API.
- Dynamic Razorpay subscription checkout creation using Razorpay API.
- Live deployment to Render/Fly.
- Real Supabase project wiring.
- Real DigitalOcean/Tailscale provisioning test with credentials.
- LAN direct connection fallback.
- Proper Codex/Claude approval and diff parsers.
- Encrypted workspace snapshot upload/restore.
- Production Signal double-ratchet implementation or security audit.

## Blunt Security Boundary

The current daemon has real encrypted envelopes, but it is not yet a full audited Signal Protocol implementation. Also, in cloud mode, the cloud runner necessarily sees the working tree because Codex/Claude executes there.
