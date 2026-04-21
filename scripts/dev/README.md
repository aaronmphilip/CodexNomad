# Codex Nomad Local Dev Scripts

These scripts are for Windows local PC-on testing with a real Android phone.

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
