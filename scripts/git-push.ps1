# Push to origin using project-local PAT (config/github.pat.local - gitignored).
# Usage: .\scripts\git-push.ps1 [branch]
param(
  [string]$Branch = "main"
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$patFile = Join-Path $root "config\github.pat.local"
if (-not (Test-Path $patFile)) {
  Write-Error "Missing config/github.pat.local - add GitHub PAT for ANANDU-2000/PurchaseAssiastant."
}
$pat = (Get-Content $patFile -Raw).Trim()
if ($pat.Length -lt 10) {
  Write-Error "PAT in config/github.pat.local looks empty."
}
$remote = "https://ANANDU-2000:${pat}@github.com/ANANDU-2000/PurchaseAssiastant.git"
Write-Host "Pushing $Branch to PurchaseAssiastant..."
git push $remote "${Branch}:${Branch}"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git fetch origin $Branch 2>$null
$sha = git rev-parse --short "origin/$Branch" 2>$null
Write-Host "Push complete. origin/$Branch at $sha"
