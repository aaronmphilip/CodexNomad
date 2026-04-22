# Codex Nomad Daemon

Codex Nomad is the Android-first remote-control layer for Codex and Claude Code. The daemon is a single Go binary that wraps the official CLI, creates a fresh encrypted session, displays a QR pairing code, and streams terminal/file events through the relay as ciphertext.

## Free local mode

Local test install from this repo on Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\install-local-windows.ps1
```

Local test install from this repo on macOS or Linux:

```sh
sh scripts/dev/install-local-unix.sh
```

The public installer URLs below are for the future hosted release channel. They
will fail until `codexnomad.pro` serves the installer scripts and release
archives.

Future hosted install on Windows PowerShell:

```powershell
irm https://codexnomad.pro/install.ps1 | iex
```

Future hosted install on macOS or Linux:

```sh
curl -fsSL https://codexnomad.pro/install | sh
```

Running the installer again updates the daemon in place.

For local phone testing before `codexnomad.pro` is deployed, start the relay and
agent session from the repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-local-test-windows.ps1 -Agent claude
```

For Codex on Windows, the Codex desktop app binary is not enough. Install the
Codex CLI first:

```powershell
npm.cmd install -g @openai/codex
codex.cmd login
```

Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-local-test-windows.ps1 -Agent codex
```

After the hosted relay is deployed, start a Codex session directly:

```sh
codexnomad codex
```

Start a Claude Code session directly:

```sh
codexnomad claude
```

Then open the Android app, tap `New Session`, scan the QR code, and control the live terminal from the phone. Local mode requires the laptop/PC to stay powered on because the official CLI process is running there.

Useful service commands:

```sh
codexnomad install
codexnomad start
codexnomad status
codexnomad logs
codexnomad doctor
codexnomad stop
```

Local packaging smoke test:

```sh
sh scripts/release/package-daemon-unix.sh
CODEXNOMAD_ARCHIVE="$PWD/dist/codexnomad_linux_amd64.tar.gz" \
CODEXNOMAD_INSTALL_DIR="$PWD/.tools/installer-unix/bin" \
CODEXNOMAD_NO_SERVICE=1 \
CODEXNOMAD_SKIP_DOCTOR=1 \
sh ./install.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\package-daemon-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ArchivePath .\dist\codexnomad_windows_amd64.zip -InstallDir .\.tools\installer-smoke\bin -NoService -NoPath -SkipDoctor
.\.tools\installer-smoke\bin\codexnomad.exe --help
```

Production verification on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci\verify-production-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\qa\local-e2e-smoke-windows.ps1
```

Headless cloud worker command used by provisioned droplets:

```sh
CODEXNOMAD_MODE=cloud codexnomad cloud-worker
```

## Cloud mode

Cloud runners are provisioned by the backend on DigitalOcean. The provisioner installs this same daemon binary on the droplet, enrolls the node into Tailscale with a short-lived tagged auth key, and starts sessions with:

```sh
CODEXNOMAD_MODE=cloud CODEXNOMAD_AGENT=codex codexnomad cloud-worker
CODEXNOMAD_MODE=cloud CODEXNOMAD_AGENT=claude codexnomad cloud-worker
```

For PC-off mode to be real, the project must already be available to the cloud runner. The supported v1 paths are:

- Clone a Git repo into the droplet workspace.
- Restore an encrypted workspace snapshot uploaded before the laptop turns off.

After that, the Android app controls the cloud session exactly like local mode, but the user laptop can be completely off.

## Configuration

```sh
export CODEXNOMAD_RELAY_URL=wss://relay.codexnomad.pro/v1/relay
export CODEXNOMAD_RELAY_TOKEN=shared-relay-token
export CODEXNOMAD_REQUIRE_RELAY=1
export CODEXNOMAD_CODEX_BIN=codex
export CODEXNOMAD_CLAUDE_BIN=claude
```

## Flutter app and relay integration

The backend/relay service lives in `services/relay`; deployment and webhook setup are documented in `docs/backend.md`.
The Android app source lives in `apps/android/flutter-app`; build and pairing setup are documented in `docs/flutter-app.md`.

The QR code contains:

```json
{
  "v": 1,
  "sid": "session id",
  "agent": "codex or claude",
  "mode": "local or cloud",
  "relay_url": "wss://relay.codexnomad.pro/v1/relay",
  "public_key": "daemon X25519 public key",
  "created_at": "RFC3339",
  "expires_at": "RFC3339"
}
```

The Flutter app scans `codexnomad://pair?data=<base64url-json>`, generates its own ephemeral X25519 keypair, connects to the relay, and sends:

```json
{
  "type": "mobile_hello",
  "sid": "session id",
  "role": "mobile",
  "public_key": "mobile X25519 public key"
}
```

The daemon replies with `daemon_ready`. After that, all app and daemon payloads use `type: ciphertext`. The relay routes by `sid` only and never receives plaintext terminal output, prompts, diffs, file content, or commands.

Before pairing, run:

```sh
codexnomad doctor
```

It checks machine identity, runtime write access, relay health, trusted phone state, and Codex/Claude CLI availability. A failing relay check means the phone cannot connect yet.

Encrypted app command types:

- `stdin` with `{ "text": "..." }`
- `interrupt`
- `approve`
- `reject`
- `file_list`
- `file_read` with `{ "path": "lib/main.dart" }`
- `file_write` with `{ "path": "lib/main.dart", "encoding": "base64", "content": "..." }`
- `ping`

Encrypted daemon event types:

- `session_started`
- `session_ready`
- `terminal_output`
- `permission_requested`
- `permission_resolved`
- `file_snapshot`
- `file_content`
- `file_saved`
- `process_exit`
- `error`
- `pong`

## Security model

Each session creates a fresh ephemeral keypair. Payloads are encrypted with X25519 shared secrets and XChaCha20-Poly1305 envelopes. The relay sees session IDs and ciphertext only.

Blunt boundary: when running in cloud mode, the DigitalOcean droplet necessarily sees the working tree because Codex/Claude executes there. The relay and subscription backend must never see code or terminal plaintext.
