# Quick pre-release checks (local). Does not deploy.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "=== Backend health test ===" -ForegroundColor Cyan
Push-Location (Join-Path $root "backend")
python -m pytest tests/test_health.py -q --tb=short
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Write-Host "`n=== Flutter analyze ===" -ForegroundColor Cyan
Push-Location (Join-Path $root "flutter_app")
flutter analyze
$analyzeExit = $LASTEXITCODE
Pop-Location

if ($analyzeExit -ne 0) {
  Write-Host "`nAnalyze reported issues (see above). Fix errors before release." -ForegroundColor Yellow
  exit $analyzeExit
}

Write-Host "`nOK: health test passed. Run full pytest and Section 7 device tests before production." -ForegroundColor Green
