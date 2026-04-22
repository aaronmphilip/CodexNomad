# Production Readiness

This is the release bar for Codex Nomad Local Mode.

## Current Production Gate

Before a store build or public release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci\verify-production-windows.ps1 -RequireCleanWorktree
```

Before real phone QA:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\qa\local-e2e-smoke-windows.ps1
```

GitHub Actions runs the same core checks on `main` and pull requests:

- daemon Go formatting, tests, and build
- relay Go formatting, tests, and build
- macOS/Linux daemon release archive packaging
- Unix installer smoke install from a local archive
- Windows daemon release archive packaging
- Windows installer smoke install from a local archive
- Flutter dependency restore
- Flutter analyze
- Flutter tests
- Android debug APK build
- Android release AAB build with a CI-only signing key

The local E2E smoke script also proves the relay, daemon, pairing URI, E2EE handshake, encrypted stdin, encrypted terminal output, and plaintext-leak marker check without a physical phone.

## Local Mode Release Bar

Local Mode is releasable only when all of these are true:

- `codexnomad doctor` passes for the target agent and relay URL.
- A real Android phone pairs by QR in under 60 seconds.
- Codex and Claude Code both stream terminal output to the app.
- Permission cards appear for real approval prompts.
- Approve, deny, and interrupt resolve the active card in the app.
- The relay never logs plaintext prompt/code/diff content with leak markers enabled.
- Reconnect works while the same daemon session is still alive.
- Debug APK and release AAB both build from a clean checkout.

## What Cannot Be Claimed Yet

Do not claim these until they are actually verified:

- production security audit
- Signal Protocol or double-ratchet security
- laptop-off completion for arbitrary workspaces
- Play Store production availability
- cloud runner reliability
- no-leak guarantee for cloud runner machines

Accurate claim today:

> Local agent control uses end-to-end encrypted command and event payloads. The relay routes session metadata and ciphertext only. In cloud mode, the runner necessarily sees the working tree because Codex or Claude executes there.

## Store Upload Bar

Before Google Play internal testing:

- Replace the dev/CI upload key with the real Play upload key.
- Store the real key outside the repo.
- Put only ignored `android/key.properties` on the release machine.
- Run `verify-production-windows.ps1 -RequireCleanWorktree`.
- Upload `apps/android/flutter-app/build/app/outputs/bundle/release/app-release.aab`.

## Desktop Installer Bar

Before publishing `https://codexnomad.pro/install.ps1` or
`https://codexnomad.pro/install`:

- Build the macOS/Linux daemon archives:

```sh
sh scripts/release/package-daemon-unix.sh
```

- Build the Windows daemon archive:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\package-daemon-windows.ps1
```

- Smoke-install without touching the real user PATH or logon task:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 `
  -ArchivePath .\dist\codexnomad_windows_amd64.zip `
  -InstallDir .\.tools\installer-smoke\bin `
  -NoService `
  -NoPath `
  -SkipDoctor
```

- Verify:

```powershell
.\.tools\installer-smoke\bin\codexnomad.exe --help
```

The Windows installer is intentionally idempotent. Running it again is the
update flow: it stops the existing daemon if possible, replaces the binary,
refreshes PATH if needed, reinstalls the logon task, and runs doctor.

The Unix installer is also intentionally idempotent. Running it again downloads
the latest archive, stops the existing daemon if possible, replaces the binary,
refreshes systemd/launchd where supported, and runs doctor.
