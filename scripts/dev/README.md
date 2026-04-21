# Codex Nomad Local Dev Scripts

These scripts are for Windows local PC-on testing with a real Android phone.

Fast path:

Run this once if Android Studio cannot build `sodium` because it cannot find `bash.exe` or `make.exe`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\configure-android-studio-env-windows.ps1
```

Then close Android Studio completely and reopen it.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-local-test-windows.ps1
```

That starts the local relay and a Codex session in separate PowerShell windows. Use `-Agent claude` for Claude Code:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-local-test-windows.ps1 -Agent claude
```

To also run the Flutter app from the script when a wireless Android device is already connected:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-local-test-windows.ps1 -RunApp
```

To test QR/E2EE without the official Codex CLI installed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-local-test-windows.ps1 -Agent demo
```

Manual path:

1. Start the relay:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\run-relay-local-windows.ps1
```

2. In another PowerShell window, start a daemon session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\run-daemon-codex-local-windows.ps1
```

or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\run-daemon-claude-local-windows.ps1
```

3. Build the Android debug APK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\build-android-arm64-windows.ps1
```

The APK is written to:

```text
apps\android\flutter-app\build\app\outputs\flutter-apk\app-debug.apk
```

For phone testing, the PC and phone must be on the same Wi-Fi network. If Windows Firewall asks, allow the relay on private networks.
