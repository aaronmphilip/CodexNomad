# Android Release Packaging

## Current Output

Debug APK:

```sh
apps/android/flutter-app/build/app/outputs/flutter-apk/app-debug.apk
```

Release App Bundle:

```sh
apps/android/flutter-app/build/app/outputs/bundle/release/app-release.aab
```

## Signing

Release signing is configured from:

```sh
apps/android/flutter-app/android/key.properties
```

That file is intentionally ignored by git. Use `key.properties.example` as the template.

For local packaging tests, this workspace has an ignored dev upload key under:

```sh
apps/android/flutter-app/android/keystores/
```

Do not ship the app to Play Console with the dev key. Generate a real upload key, store it outside git, and update `key.properties`.

## Build Commands

```sh
cd apps/android/flutter-app
flutter build apk --debug --no-pub
flutter build appbundle --release --no-pub
```

## Production Checklist

- Replace the local dev upload key with the real Play upload key.
- Store signing passwords in a private password manager or CI secret store.
- Build with production `--dart-define` values for backend, Supabase, and Firebase.
- Upload the AAB to a closed internal test track before any public release.
