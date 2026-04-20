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

## Verified

Using a local Go toolchain:

- `go mod tidy`
- `go build ./cmd/daemon`
- `go test ./...`
- `bin/codexnomad.exe status`

## Not Built Yet

- Relay server.
- Flutter Android app.
- Supabase auth/trial backend.
- DigitalOcean provisioner.
- Tailscale enrollment flow.
- Polar/Razorpay subscription webhooks.
- Production Signal double-ratchet implementation or security audit.

## Blunt Security Boundary

The current daemon has real encrypted envelopes, but it is not yet a full audited Signal Protocol implementation. Also, in cloud mode, the cloud runner necessarily sees the working tree because Codex/Claude executes there.
