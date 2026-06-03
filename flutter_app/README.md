# HEXA — Flutter app

## Prerequisite

Install [Flutter](https://docs.flutter.dev/get-started/install) (includes Dart). This folder is a **source scaffold**; after installing Flutter, generate platform projects:

```bash
cd flutter_app
flutter create . --project-name harisree_warehouse
```

This adds `android/`, `ios/`, `web/`, etc., without overwriting `lib/` (confirm when prompted).

Then:

```bash
flutter pub get
flutter run
```

## API base URL (`API_BASE_URL`)

The client reads the backend URL from `--dart-define` (see [`lib/core/config/app_config.dart`](lib/core/config/app_config.dart)). Default: `http://localhost:8000`.

| Target | Example command |
|--------|-----------------|
| **Chrome / desktop** (API on same machine) | `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000` |
| **Android emulator** (API on host) | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000` |
| **Physical device** (same LAN) | Use your PC LAN IP, e.g. `--dart-define=API_BASE_URL=http://192.168.1.10:8000` |

Ensure the FastAPI server is running and `CORS` allows your web origin (dev defaults in backend settings).

### Vercel (Flutter web)

The repo root [`vercel.json`](../vercel.json) runs `scripts/vercel-flutter-build.sh` and publishes `flutter_app/build/web`.

1. In Vercel → Project → Settings: **Root Directory** = repository root (`.`), not `flutter_app` only (unless you adjust paths).
2. **Environment variables (Production):** `API_BASE_URL=https://my-purchases-api.onrender.com` and `GOOGLE_OAUTH_CLIENT_ID=<your Web client ID>` (same as backend `GOOGLE_OAUTH_CLIENT_IDS`).
3. Redeploy. A `404 NOT_FOUND` at the project URL usually meant the static `build/web` output was missing or the Root Directory pointed at the wrong folder.

**Production URL (bookmarked):** [https://purchase-assiastant.vercel.app](https://purchase-assiastant.vercel.app) — note the spelling (`assiastant`, not `assistant`). The hostname `purchase-assistant.vercel.app` is a different Vercel project and serves HTML instead of `main.dart.js`, which shows a blank gray screen with no tabs.

## Sign in with Google (App Store / Play / web)

Fast onboarding uses **Google Sign-In** in the app and **`POST /v1/auth/google`** on the API.

1. **Google Cloud Console** ([APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials)): create or pick a project, enable **Google+** / People API if prompted, then:
   - Create an OAuth **Web application** client. Copy the **Client ID** (ends with `.apps.googleusercontent.com`). This is what the Flutter plugin uses as `serverClientId` so the ID token’s audience matches your backend.
   - Create an OAuth **iOS** client with your app’s **Bundle ID** (e.g. from Xcode / `ios/Runner.xcodeproj`).
   - For **Android**, create an OAuth **Android** client with your **package name** and **SHA-1** (debug and release keystores as needed).

2. **Backend** — set in `backend/.env` (same Web client ID as below):

   `GOOGLE_OAUTH_CLIENT_IDS=<your-web-client-id.apps.googleusercontent.com>`

   You can list multiple client IDs separated by commas if you ever verify tokens from more than one audience.

3. **Flutter** — pass the **Web** client ID at build time (must match the API):

   `flutter run --dart-define=GOOGLE_OAUTH_CLIENT_ID=<same-web-client-id> --dart-define=API_BASE_URL=...`

4. **iOS** — add the **reversed iOS client ID** as a URL scheme in `ios/Runner/Info.plist` (see [google_sign_in iOS setup](https://pub.dev/packages/google_sign_in#ios)). Use the value from Google’s **iOS** OAuth client (format `com.googleusercontent.apps.<numbers-and-id>`). Without this, Google returns to your app after sign-in on the App Store build.

5. **Database** — Google-only users have **no password** (`password_hash` null). If you already had a `users` table, run a migration or recreate the DB so `password_hash` is nullable and `google_sub` exists (see `backend/app/models/user.py`).

## Environment / API keys (what matters for current MVP)

The app only needs a **running backend** with a valid `DATABASE_URL` and JWT settings. See the repo root [`.env.example`](../.env.example).

**Required for local sign-in + entries:** `DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET`. Register a user via the app (Create account) or `POST /v1/auth/register`.

**Not required until those features are built in the app:** `OPENAI_API_KEY`, `OCR_*`, `STT_*`, `DIALOG360_*`, `S3_*`, `RAZORPAY_*` (Phase 2–4 integrations).

## Layout

Matches [docs/flutter-architecture.md](../docs/flutter-architecture.md): `lib/core`, `lib/features/*`, bottom nav (Home, Entries, Analytics, Contacts, Settings).

## Testing

```bash
flutter analyze
flutter test
```

If `flutter test` fails deleting `build\` (e.g. OneDrive locks), remove `flutter_app/build` manually and retry.
