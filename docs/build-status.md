# Codex Nomad Build Status

## Product

Codex Nomad is a premium phone-first operations center for local and cloud coding agents.

The core promise:

- Free tier: control a Codex or Claude session running on the user's laptop or PC.
- Pro tier: run sessions on an automatically provisioned cloud machine so the laptop can be off.
- Relay and backend must not see plaintext code, prompts, terminal output, diffs, or file contents.

## Built So Far

Daemon foundation:

- `codexnomad pair`
- `codexnomad codex`
- `codexnomad claude`
- `codexnomad install`
- `codexnomad start`
- `codexnomad status`
- `codexnomad stop`
- `codexnomad logs`

Security/session layer:

- Per-session X25519 keypair.
- X25519 plus XChaCha20-Poly1305 encrypted envelopes.
- QR pairing payload with session id, relay URL, agent, mode, public key, machine id/name/OS, creation time, and expiry.
- Stable local machine identity stored under the daemon config directory.
- Stable mobile session key seed stored in secure storage, enabling same-phone reconnect to a live local session after QR expiry.
- Trusted mobile device registry stored on the local machine, with list/revoke commands and per-command authorization checks.
- Encrypted envelope sequence binding and inbound replay checks on daemon and mobile.
- Relay contract where relay sees session id and ciphertext only.
- Local readiness doctor for machine identity, writable runtime state, relay health, trusted phone state, and Codex/Claude CLI availability.

Runtime:

- Codex/Claude subprocess wrapper.
- Headless `codexnomad cloud-worker` for cloud droplets.
- Cloud worker pairing metadata registration.
- Unix PTY support.
- Windows stdin/stdout fallback.
- Terminal output streaming.
- Mobile command handling for stdin, interrupt, approve, reject, file list, file read, file write, and ping.
- Permission resolution events after approve/reject/interrupt so mobile review cards clear when a decision is sent.

Files:

- Git-aware changed-file snapshot.
- Git diff event emission for staged and unstaged local changes.
- Safe relative-path read/write guard.
- Large-file read limit.

Flutter local app:

- Free Local Mode first-screen experience.
- Black/purple premium dark theme.
- Bricolage Grotesque typography.
- Phosphor icon system.
- Agent Inbox home screen.
- Local Machines screen for paired machine status and reconnect.
- Review-first live session navigation.
- Structured attention items for permission requests, diffs, disconnects, exits, and errors.
- Privacy-safe local notification hooks for attention events.
- Last-machine display and reconnect action.

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

Using the local toolchain:

- daemon `go test ./...`
- relay `go test ./...`
- Flutter `flutter analyze --no-pub`
- Flutter `flutter test --no-pub`
- Flutter `flutter build apk --debug --no-pub`
- Flutter `flutter build appbundle --release --no-pub`

## Not Built Yet

- Real production Play upload key and Play Console internal testing.
- Dynamic Polar checkout creation using Polar API.
- Dynamic Razorpay subscription checkout creation using Razorpay API.
- Live deployment to Render/Fly.
- Real Supabase project wiring.
- Real DigitalOcean/Tailscale provisioning test with credentials.
- LAN direct connection fallback.
- Proper Codex/Claude approval and diff parsers.
- Encrypted workspace snapshot upload/restore.
- Production Signal double-ratchet implementation or security audit.

## Current Android Build Output

Debug APK builds locally at `apps/android/flutter-app/build/app/outputs/flutter-apk/app-debug.apk`.

Release AAB builds locally at `apps/android/flutter-app/build/app/outputs/bundle/release/app-release.aab`.

The Flutter app no longer depends on native `sodium`; mobile E2EE uses the pure-Dart `cryptography` package, so the Android build does not require Git Bash/MSYS `make`.

Release signing is wired through ignored `android/key.properties`. The current local key is a dev upload key only, not the production Play upload key.

## Blunt Security Boundary

The current daemon has real encrypted envelopes, but it is not yet a full audited Signal Protocol implementation. Also, in cloud mode, the cloud runner necessarily sees the working tree because Codex/Claude executes there.
