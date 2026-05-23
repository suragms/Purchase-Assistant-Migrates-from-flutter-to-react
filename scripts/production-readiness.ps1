# Harisree / Purchase Assistant — pre-production smoke (no secrets).
# Run from repo root: powershell -File scripts/production-readiness.ps1
$ErrorActionPreference = "Continue"

$renderHealth = "https://my-purchases-api.onrender.com/health"
$renderReady = "https://my-purchases-api.onrender.com/health/ready"
$vercelApp = "https://purchase-assiastant.vercel.app"

function Test-Get {
  param([string]$Url, [string]$Label)
  Write-Host "`n=== $Label ===" -ForegroundColor Cyan
  try {
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60
    Write-Host "OK $($r.StatusCode)"
    if ($r.Content.Length -lt 600) { Write-Host $r.Content }
    return $true
  } catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
}

$allOk = $true
if (-not (Test-Get $renderHealth "Render /health")) { $allOk = $false }
if (-not (Test-Get $renderReady "Render /health/ready (DB)")) { $allOk = $false }
if (-not (Test-Get $vercelApp "Vercel web shell")) { $allOk = $false }

Write-Host "`n=== Backend pytest ===" -ForegroundColor Cyan
Push-Location (Join-Path $PSScriptRoot "..\backend")
try {
  $pytest = python -m pytest -q --tb=no 2>&1 | Out-String
  Write-Host $pytest.TrimEnd()
  if ($pytest -match "(\d+) failed") {
    if ([int]$Matches[1] -gt 0) { $allOk = $false }
  }
} catch {
  Write-Host "pytest not run: $_" -ForegroundColor Yellow
} finally {
  Pop-Location
}

Write-Host "`n=== API inventory ===" -ForegroundColor Cyan
$routesFile = Join-Path $PSScriptRoot "..\backend\scripts\_api_routes.txt"
if (Test-Path $routesFile) {
  $n = (Get-Content $routesFile | Select-String "^(GET|POST|PUT|PATCH|DELETE)" | Measure-Object).Count
  Write-Host "~$n FastAPI routes (see backend/scripts/_api_routes.txt)"
} else {
  Write-Host "Run: cd backend; python scripts/list_routes.py > scripts/_api_routes.txt"
}

Write-Host "`n=== Client API base (reminder) ===" -ForegroundColor Cyan
Write-Host "Production web uses API_BASE_URL=https://my-purchases-api.onrender.com (vercel.json)"
Write-Host "Local dev default is http://127.0.0.1:8000 — start uvicorn or use:"
Write-Host "  flutter run --dart-define=API_BASE_URL=https://my-purchases-api.onrender.com"

if (-not $allOk) {
  Write-Host "`nSome checks FAILED — not production-ready until fixed." -ForegroundColor Red
  exit 1
}
Write-Host "`nInfra smoke PASSED. Still manually sign in and tap each main tab once." -ForegroundColor Green
