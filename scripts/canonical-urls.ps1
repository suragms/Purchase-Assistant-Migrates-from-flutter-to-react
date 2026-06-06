# Single source of truth — Harisree production URLs (bookmark / CORS / smoke tests).
$ErrorActionPreference = "Stop"

$script:CanonicalWeb = "https://purchase-assiastant.vercel.app"
$script:CanonicalApi = "https://my-purchases-api.onrender.com"
$script:WrongWebHosts = @(
  "https://purchase-assistant.vercel.app",
  "https://purchase-assastant.vercel.app"
)

function Get-CanonicalWeb { $script:CanonicalWeb }
function Get-CanonicalApi { $script:CanonicalApi }

if ($MyInvocation.InvocationName -ne '.') {
  Write-Host "Canonical web: $script:CanonicalWeb"
  Write-Host "Canonical API: $script:CanonicalApi"
  Write-Host "Do NOT use: $($script:WrongWebHosts -join ', ')"
}
