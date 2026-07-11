# Render service settings checklist — align live my-purchases-api with render.yaml.
# MCP cannot update web service build settings; apply in Dashboard:
# https://dashboard.render.com/web/srv-d7ea0il8nd3s73e4fvl0/settings
$ErrorActionPreference = "Stop"

Write-Host "Render service sync checklist (my-purchases-api)" -ForegroundColor Cyan
Write-Host ""
Write-Host "General:"
Write-Host "  rootDir:              backend-dotnet"
Write-Host "  runtime:              Docker"
Write-Host "  branch:               main"
Write-Host "  autoDeploy:           Yes"
Write-Host ""
Write-Host "Build & Deploy (Dockerfile in rootDir):"
Write-Host "  buildCommand:         docker build -t my-purchases-api ."
Write-Host "  startCommand:         (Dockerfile ENTRYPOINT)"
Write-Host "  healthCheckPath:      /health/live"
Write-Host ""
Write-Host "Environment (merge, do not wipe secrets):"
Write-Host "  APP_ENV=production"
Write-Host "  ASPNETCORE_ENVIRONMENT=Production"
Write-Host "  ConnectionStrings__DefaultConnection=(Render Postgres DB)"
Write-Host "  LOG_LEVEL=Warning  (appsettings.Production.json)"
Write-Host "  CORS_ORIGINS includes https://purchase-assiastant.vercel.app (canonical web)"
Write-Host ""
Write-Host "After saving, Manual Deploy once, then:"
Write-Host "  powershell -File scripts/verify-deploy.ps1"
