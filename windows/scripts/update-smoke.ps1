$ErrorActionPreference = 'Stop'
$root = Join-Path $env:RUNNER_TEMP 'ftr-update-e2e'
$baseline = Join-Path $root 'baseline'
$installed = Join-Path $root 'installed'
$portFile = Join-Path $root 'port.txt'
New-Item -ItemType Directory -Path $root -Force | Out-Null
Copy-Item 'windows/dist/installer/win-unpacked' $baseline -Recurse
$metaPath = Join-Path $baseline 'resources/app/package.json'
$meta = Get-Content $metaPath -Raw | ConvertFrom-Json
$meta.version = '0.0.1'
$meta.main = 'update-smoke-main.js'
$meta | ConvertTo-Json -Depth 100 | Set-Content $metaPath -Encoding utf8
Copy-Item 'windows/scripts/update-smoke-main.js' (Join-Path $baseline 'resources/app/update-smoke-main.js')
# The lower version is synthetic; all update orchestration uses production code.
Push-Location windows
try {
  & npx electron-builder --config electron-builder.json --win nsis --x64 --publish never --prepackaged $baseline --config.extraMetadata.version=0.0.1 --config.directories.output="$root/baseline-installer"
  if ($LASTEXITCODE -ne 0) { throw 'Baseline installer build failed' }
} finally { Pop-Location }
$setup = Get-ChildItem "$root/baseline-installer/*Setup.exe" | Select-Object -First 1
$p = Start-Process $setup.FullName -ArgumentList @('/S', "/D=$installed") -PassThru -Wait
if ($p.ExitCode -ne 0) { throw "Baseline installation failed: $($p.ExitCode)" }
$env:FISHTOUCHING_SMOKE_ROOT = Join-Path $root 'library'
$env:FISHTOUCHING_UPDATE_EXPECTED_VERSION = (Get-Content windows/package.json | ConvertFrom-Json).version
$server = Start-Process node -ArgumentList @('windows/scripts/update-test-server.js','windows/dist/installer', $portFile) -PassThru
try {
  for ($i=0; $i -lt 30 -and !(Test-Path $portFile); $i++) { Start-Sleep 1 }
  $port = Get-Content $portFile
  $env:FISHTOUCHING_UPDATE_TEST_URL = "http://127.0.0.1:$port/"
  Start-Process (Join-Path $installed 'FishTouching Reader.exe')
  $ok = Join-Path $env:FISHTOUCHING_SMOKE_ROOT 'smoke-ok.txt'
  $failed = Join-Path $env:FISHTOUCHING_SMOKE_ROOT 'upgrade-failed.txt'
  for ($i=0; $i -lt 180 -and !(Test-Path $ok) -and !(Test-Path $failed); $i++) { Start-Sleep 1 }
  Get-Content "$env:FISHTOUCHING_SMOKE_ROOT/upgrade-dialogs.txt" -ErrorAction SilentlyContinue
  Get-Content "$env:FISHTOUCHING_SMOKE_ROOT/upgrade-errors.txt" -ErrorAction SilentlyContinue
  Get-Content "$env:FISHTOUCHING_SMOKE_ROOT/startup.log" -ErrorAction SilentlyContinue
  if (Test-Path $failed) { throw (Get-Content $failed -Raw) }
  if (!(Test-Path $ok)) { throw 'Upgrade/relaunch did not complete' }
  if (!(Test-Path "$env:FISHTOUCHING_SMOKE_ROOT/upgrade-download-ok.txt")) { throw 'Updater download was not exercised' }
  Write-Output (Get-Content $ok)
  $actual = Get-Content "$installed/resources/app/package.json" | ConvertFrom-Json
  if ($actual.version -ne $env:FISHTOUCHING_UPDATE_EXPECTED_VERSION -or $actual.main -ne 'main.js') { throw 'Production app was not installed' }
} finally {
  Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
  Get-Process 'FishTouching Reader' -ErrorAction SilentlyContinue | Where-Object { $_.Path.StartsWith($root) } | Stop-Process -Force
  Remove-Item Env:FISHTOUCHING_UPDATE_EXPECTED_VERSION -ErrorAction SilentlyContinue
  Remove-Item Env:FISHTOUCHING_UPDATE_TEST_URL -ErrorAction SilentlyContinue
  Remove-Item Env:FISHTOUCHING_SMOKE_ROOT -ErrorAction SilentlyContinue
}
