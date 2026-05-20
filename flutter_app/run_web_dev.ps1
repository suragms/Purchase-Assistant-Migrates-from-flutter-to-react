# Customer app (Flutter web).
#
# DEBUG (default): DDC serves 1000+ small .dart.lib.js files — first paint is SLOW,
# especially with Chrome DevTools → Network throttling (e.g. "Fast 4G"). That is normal;
# turn throttling OFF while testing debug web, or use -Release for a realistic load time.
#
# RELEASE (-Release): one main bundle — loads like production (no hot reload).
#
# You MUST pass --no-web-resources-cdn so CanvasKit is served from this machine (/canvaskit/).
# web/flutter_bootstrap.js sets canvasKitBaseUrl and canvasKitVariant: full — keep in sync.
# Use full Chrome to verify UI; embedded Simple Browser often cannot composite the Flutter canvas.
#
# 1) Start API (separate terminal, repo root):  .\scripts\start-api-local.ps1
#    Or open http://127.0.0.1:8000/docs — if it does not load, Flutter will show connection errors.
# 2) Run (debug):  .\run_web_dev.ps1
#    Run (fast):   .\run_web_dev.ps1 -Release
#    Port in use:  .\run_web_dev.ps1 -WebPort 8081

param(
  [switch] $Release,
  [int] $WebPort = 8080
)

Set-Location $PSScriptRoot

$flutterArgs = @(
  'run', '-d', 'chrome',
  '--web-port', "$WebPort",
  '--no-web-resources-cdn',
  '--dart-define=API_BASE_URL=http://127.0.0.1:8000'
)
if ($Release) {
  $flutterArgs += '--release'
}

& flutter @flutterArgs
