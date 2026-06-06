# Smoke-check live Render + Vercel after deploy (no secrets required).
$ErrorActionPreference = "Stop"

$renderHealth = "https://my-purchases-api.onrender.com/health"
$renderReady = "https://my-purchases-api.onrender.com/health/ready"
# Canonical Harisree Flutter web (spelling: assiastant — not assistant).
$vercelCanonical = "https://purchase-assiastant.vercel.app"
# Wrong hostname: old React "PurchaseAI" deployment — always blank for Harisree routes.
$vercelWrongHost = "https://purchase-assistant.vercel.app"
$expectedAlembic = "060_stock_list_performance_indexes"

function Test-UrlOk {
  param([string]$Url, [string]$Label)
  Write-Host ""
  Write-Host "=== $Label ===" -ForegroundColor Cyan
  try {
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 90
    Write-Host "OK $($r.StatusCode) $Url"
    return @{ Ok = $true; Body = $r.Content }
  } catch {
    Write-Host "FAIL $Url - $($_.Exception.Message)" -ForegroundColor Red
    return @{ Ok = $false; Body = $null }
  }
}

function Test-FlutterJsBundle {
  param([string]$AppBase, [string]$Label, [switch]$Required)
  Write-Host ""
  Write-Host "=== Vercel Flutter bundle ($Label) ===" -ForegroundColor Cyan
  $js = "$AppBase/main.dart.js"
  try {
    $head = Invoke-WebRequest -Uri $js -Method Head -UseBasicParsing -TimeoutSec 90
    $ct = [string]$head.Headers['Content-Type']
    $len = [string]$head.Headers['Content-Length']
    Write-Host "HEAD $js -> $($head.StatusCode) type=$ct len=$len"
    if ($head.StatusCode -ne 200) {
      if ($Required) { return $false }
      return $true
    }
    if ($ct -notmatch 'javascript') {
      Write-Host "NOT FLUTTER: main.dart.js is HTML (blank-screen cause on this hostname)." -ForegroundColor Yellow
      Write-Host "  Use canonical URL: $vercelCanonical" -ForegroundColor Yellow
      if ($Required) { return $false }
      return $true
    }
    if ($len -and [int64]$len -lt 1000000) {
      Write-Host "FAIL: main.dart.js too small ($len bytes)." -ForegroundColor Red
      return $false
    }
    Write-Host "OK: Flutter web bundle present." -ForegroundColor Green
    return $true
  } catch {
    Write-Host "FAIL $js - $($_.Exception.Message)" -ForegroundColor Red
    if ($Required) { return $false }
    return $true
  }
}

$ok = $true

$health = Test-UrlOk -Url $renderHealth -Label "Render /health"
if (-not $health.Ok) { $ok = $false }

$ready = Test-UrlOk -Url $renderReady -Label "Render /health/ready (DB + schema)"
if (-not $ready.Ok) {
  $ok = $false
} elseif ($ready.Body) {
  try {
    $payload = $ready.Body | ConvertFrom-Json
    $db = $payload.db
    $schemaOk = $payload.schema_ok
    $alembic = $payload.schema.alembic_version
    $stockSync = $payload.stock_sync_ready
    $staffV2 = $payload.schema.staff_activity_v2

    Write-Host "  db: $db"
    Write-Host "  alembic_version: $alembic"
    Write-Host "  stock_sync_ready: $stockSync"
    Write-Host "  staff_activity_v2: $staffV2"
    Write-Host "  schema_ok: $schemaOk"

    if ($db -ne "ok") {
      Write-Host "FAIL: database not ok" -ForegroundColor Red
      $ok = $false
    }
    if (-not $stockSync) {
      Write-Host "WARN: stock_sync_ready is false (delivery pipeline columns missing?)" -ForegroundColor Yellow
    }
    if ($alembic -ne $expectedAlembic) {
      Write-Host "FAIL: expected alembic $expectedAlembic, got $alembic" -ForegroundColor Red
      Write-Host "  Run: Render Shell -> cd backend && alembic upgrade head" -ForegroundColor Yellow
      Write-Host "  Or set AUTO_MIGRATE=1 and redeploy once." -ForegroundColor Yellow
      $ok = $false
    }
    if ($null -ne $schemaOk -and -not $schemaOk) {
      Write-Host "WARN: schema_ok is false (migration 059 staff activity CHECK may be missing)" -ForegroundColor Yellow
      if ($alembic -ne $expectedAlembic) { $ok = $false }
    }
  } catch {
    Write-Host "WARN: could not parse /health/ready JSON: $_" -ForegroundColor Yellow
  }
}

# Warn if wrong hostname still serves non-Flutter content (common blank-screen mistake).
Test-FlutterJsBundle -AppBase $vercelWrongHost -Label "wrong host (assistant)" | Out-Null

$shell = Test-UrlOk -Url $vercelCanonical -Label "Vercel canonical shell ($vercelCanonical)"
if (-not $shell.Ok) {
  $ok = $false
} elseif (-not (Test-FlutterJsBundle -AppBase $vercelCanonical -Label "canonical (assiastant)" -Required)) {
  $ok = $false
}

Write-Host ""
Write-Host "=== Vercel service worker (must not reload-loop) ===" -ForegroundColor Cyan
try {
  $swUrl = "$vercelCanonical/flutter_service_worker.js"
  $sw = Invoke-WebRequest -Uri $swUrl -UseBasicParsing -TimeoutSec 30
  if ($sw.StatusCode -eq 200 -and ($sw.Content -match 'client\.navigate' -or $sw.Content -match 'unregister\(')) {
    Write-Host "WARN: $swUrl looks like a reload-loop SW - redeploy with --pwa-strategy=none and no SW register." -ForegroundColor Yellow
  } elseif ($sw.StatusCode -eq 404) {
    Write-Host "OK: no service worker file (expected with --pwa-strategy=none)." -ForegroundColor Green
  } else {
    Write-Host "OK: $swUrl present (review if caching is intentional)." -ForegroundColor Green
  }
} catch {
  if ($_.Exception.Response.StatusCode.value__ -eq 404) {
    Write-Host "OK: no service worker file (expected)." -ForegroundColor Green
  } else {
    Write-Host "WARN: could not fetch service worker: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

if (-not $ok) {
  Write-Host ""
  Write-Host "Deploy smoke FAILED." -ForegroundColor Red
  Write-Host "Render dashboard: https://dashboard.render.com/web/srv-d7ea0il8nd3s73e4fvl0/settings" -ForegroundColor Yellow
  Write-Host "Vercel: open ONLY $vercelCanonical (not purchase-assistant.vercel.app)." -ForegroundColor Yellow
  Write-Host "Fix wrong domain: Vercel -> purchase-assistant project -> Settings -> Domains -> Redirect to purchase-assiastant.vercel.app" -ForegroundColor Yellow
  exit 1
}

Write-Host ""
Write-Host "Deploy smoke: Render + canonical Vercel Flutter OK (alembic $expectedAlembic)." -ForegroundColor Green
Write-Host "Bookmark: $vercelCanonical/home" -ForegroundColor Green
