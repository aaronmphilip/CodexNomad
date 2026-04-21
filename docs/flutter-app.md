# Codex Nomad Android App

## What This Builds

This is the local PC-on Android app:

- QR scan pairing from `codexnomad codex` or `codexnomad claude`.
- E2EE WebSocket relay connection using X25519 plus XChaCha20-Poly1305.
- Live terminal output.
- Chat input with microphone shortcut.
- Approve, reject, interrupt, and end session actions.
- Diff cards instead of raw JSON/XML walls.
- Changed-file and project-file browser.
- Inline editor with syntax highlighting and `Save & Push`.
- Supabase magic-link auth scaffold and session-list integration hooks.

Cloud/trial UI is intentionally not implemented in this pass.

## Security Rule

Never put `SUPABASE_SERVICE_ROLE_KEY` in Flutter. The service-role key is backend-only. The Android app must use the Supabase anon key.

The Supabase project URL for your project ref is:

```txt
https://iyuzdvioufyaoncyyqhq.supabase.co
```

The current anon key for local Flutter builds is:

```txt
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml5dXpkdmlvdWZ5YW9uY3l5cWhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2OTExNzIsImV4cCI6MjA5MjI2NzE3Mn0.f7dpD0gEzxbIXRyXKPAQERID1r-Ug8-n1c6wjQqfv24
```

Because the service-role key was pasted into chat, rotate it before production.

## Generate Android Project Files

Flutter is not installed in this workspace, so the Android Gradle wrapper was not generated here. On a machine with Flutter:

```sh
cd apps/android/flutter-app
flutter create --platforms=android .
flutter pub get
```

Add Android permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

If you enable Firebase push notifications, add `google-services.json` and standard Firebase Android setup. Push scaffolding exists, but Firebase is optional for local testing.

## Run Against Local Relay and Daemon

Terminal 1, start relay:

```sh
docker compose up --build relay
```

Terminal 2, start a Codex session:

```sh
set CODEXNOMAD_RELAY_URL=ws://localhost:8080/v1/relay
codexnomad pair
```

For Android emulator, the app uses `10.0.2.2` to reach host machine services. If using a real phone, replace URLs with your machine LAN IP:

```sh
codexnomad pair
```

Build/run app:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://iyuzdvioufyaoncyyqhq.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml5dXpkdmlvdWZ5YW9uY3l5cWhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2OTExNzIsImV4cCI6MjA5MjI2NzE3Mn0.f7dpD0gEzxbIXRyXKPAQERID1r-Ug8-n1c6wjQqfv24 \
  --dart-define=CODEXNOMAD_BACKEND_URL=http://10.0.2.2:8080
```

Then:

1. Open app.
2. Tap `Pair local`.
3. Scan the terminal QR.
4. Live Session opens.
5. Use Terminal, Chat, Files, and Editor tabs.

## Design Principles

- The app is a mobile command center, not a terminal wrapper.
- Agent events become tappable cards, not raw JSON.
- Diffs are review objects with clear Approve/Reject actions.
- The terminal remains dense and readable, but it is not the whole product.
- The file browser leads with changed files, then full project context.
- The editor is lightweight and optimized for quick fixes, not full IDE replacement.
- Visual language uses Material 3, 8px cards, precise icons, restrained color, and clear hierarchy.
- No Happy Coder UI structure is copied.

## Current Gaps

- Same-LAN direct connection is not active until the daemon exposes a LAN WebSocket URL in the QR payload.
- Push notifications need Firebase project setup.
- Proper Codex/Claude approval parsing still needs CLI-specific adapters on the daemon side.
