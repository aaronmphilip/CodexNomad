# Production Verification

Run the Windows gate before calling a local build production-ready:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci\verify-production-windows.ps1
```

Use `-RequireCleanWorktree` before release tagging or store upload.

The script runs:

- Go formatting, tests, and builds for the daemon.
- Go formatting, tests, and builds for the relay/backend.
- Flutter dependency restore.
- Dart format check.
- Flutter analyze and widget tests.
- Android debug APK build.
- Android release app bundle build.

If `apps/android/flutter-app/android/key.properties` is missing, the script creates an ignored CI-only signing key so the release bundle path is still tested. That key is not the production Play upload key.
