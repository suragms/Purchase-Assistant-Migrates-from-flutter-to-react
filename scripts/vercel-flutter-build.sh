#!/usr/bin/env bash
# Vercel build (Linux). Produces flutter_app/build/web for static hosting.
set -euo pipefail
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/flutter_app"
BUILD_LOG="/tmp/flutter-web-build.log"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.6}"
FLUTTER_ROOT="${HOME}/flutter-${FLUTTER_VERSION}"

on_fail() {
  echo "=== Vercel Flutter web build FAILED ==="
  if [ -f "$BUILD_LOG" ]; then
    echo "--- Last 100 lines of build log ---"
    tail -100 "$BUILD_LOG"
    echo "--- dart2js / compile errors (grep) ---"
    grep -E "Error:|error:|isn't defined|Compilation failed|SIGKILL|Killed" "$BUILD_LOG" || true
  fi
}
trap on_fail ERR

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${PATH}:${FLUTTER_ROOT}/bin"
fi
if ! command -v flutter >/dev/null 2>&1; then
  if [ -d "${FLUTTER_ROOT}" ]; then
    echo "Flutter directory ${FLUTTER_ROOT} already exists, skipping installation clone."
  else
    echo "Installing Flutter ${FLUTTER_VERSION}..."
    git clone https://github.com/flutter/flutter.git -b "${FLUTTER_VERSION}" --depth 1 "${FLUTTER_ROOT}" \
      || git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${FLUTTER_ROOT}"
  fi
  export PATH="${PATH}:${FLUTTER_ROOT}/bin"
fi

# dart2js OOM on Vercel often exits with code 1 and no clear "Error:" line.
export BUILD_MAX_WORKERS_PER_TASK="${BUILD_MAX_WORKERS_PER_TASK:-1}"
export DART_VM_OPTIONS="${DART_VM_OPTIONS:---max-old-space-size=3072}"

flutter config --no-analytics
flutter --version
flutter precache --web
flutter pub get

echo "Analyzing (fail fast before dart2js)..."
flutter analyze --no-fatal-infos --no-fatal-warnings

echo "Clean + build web (-O2 lowers dart2js memory vs default -O4)..."
flutter clean
flutter pub get

API_URL="${API_BASE_URL:-https://my-purchases-api.onrender.com}"
BUILD_SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# Default prod: no source maps (smaller bundle). Set ENABLE_SOURCE_MAPS=1 on a Vercel preview only.
SOURCE_MAPS_FLAG="--no-source-maps"
if [ "${ENABLE_SOURCE_MAPS:-0}" = "1" ]; then
  SOURCE_MAPS_FLAG=""
fi

echo "Building web (API=${API_URL}, BUILD_SHA=${BUILD_SHA}, SOURCE_MAPS=${ENABLE_SOURCE_MAPS:-0})..."
flutter build web --release \
  -O2 \
  --pwa-strategy=none \
  --no-web-resources-cdn \
  $SOURCE_MAPS_FLAG \
  --no-wasm-dry-run \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=BUILD_SHA="$BUILD_SHA" \
  2>&1 | tee "$BUILD_LOG"

echo "Built: $ROOT/flutter_app/build/web"
