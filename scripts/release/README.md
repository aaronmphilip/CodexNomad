# Release Packaging

Build macOS/Linux daemon release archives:

```sh
sh scripts/release/package-daemon-unix.sh
```

The archives are written to:

```text
dist/codexnomad_linux_amd64.tar.gz
dist/codexnomad_linux_arm64.tar.gz
dist/codexnomad_darwin_amd64.tar.gz
dist/codexnomad_darwin_arm64.tar.gz
```

Build the Windows daemon release archive:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\package-daemon-windows.ps1
```

The archive is written to:

```text
dist\codexnomad_windows_amd64.zip
```

Smoke-install that archive without touching the real user PATH or logon task:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 `
  -ArchivePath .\dist\codexnomad_windows_amd64.zip `
  -InstallDir .\.tools\installer-smoke\bin `
  -NoService `
  -NoPath `
  -SkipDoctor
```

Production one-command install:

```powershell
irm https://codexnomad.pro/install.ps1 | iex
```

```sh
curl -fsSL https://codexnomad.pro/install | sh
```

The Windows installer is also the updater. Running it again stops any existing
daemon, replaces `codexnomad.exe`, refreshes PATH if needed, reinstalls the
logon task, and runs `codexnomad doctor`.

The Unix installer is also idempotent. Running it again stops any existing
daemon, replaces `codexnomad`, refreshes service/autostart where supported, and
runs doctor.

Until the hosted release channel exists, use the local dev installers instead:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\install-local-windows.ps1
```

```sh
sh scripts/dev/install-local-unix.sh
```
