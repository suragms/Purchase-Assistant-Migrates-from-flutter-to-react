#!/usr/bin/env bash
# Production smoke — run after Vercel/Render deploy (CI or Cursor Automation).
set -euo pipefail

WEB_URL="${WEB_URL:-https://purchase-assiastant.vercel.app}"
API_URL="${API_URL:-https://my-purchases-api.onrender.com}"

fail=0

check_http() {
  local name="$1" url="$2" expect="${3:-200}"
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" "$url" || echo "000")
  if [ "$code" = "$expect" ]; then
    echo "OK  $name ($code) $url"
  else
    echo "FAIL $name expected $expect got $code — $url"
    fail=1
  fi
}

check_http "Flutter web" "$WEB_URL/"
check_http "API ready" "$API_URL/health/ready"

ready_json=$(curl -sS "$API_URL/health/ready" || echo "{}")
echo "$ready_json" | grep -q '"status":"ok"' || { echo "FAIL API status not ok"; fail=1; }
echo "$ready_json" | grep -q '"db":"ok"' || { echo "FAIL DB not ok"; fail=1; }
echo "$ready_json" | grep -q '"schema_ok":true' || { echo "FAIL schema_ok false"; fail=1; }

if [ "$fail" -ne 0 ]; then
  echo "Production smoke FAILED"
  exit 1
fi

echo "Production smoke PASSED (web + API + DB schema)"
