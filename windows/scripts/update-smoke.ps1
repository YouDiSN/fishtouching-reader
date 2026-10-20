$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run this test only on an isolated GitHub Windows runner' }
$library = Join-Path $env:APPDATA 'FishTouching Reader'
if (Test-Path $library) { throw 'Refusing to use an existing library for upgrade tests' }
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
$env:FTR_UPGRADE_TEST_ROOT = $library
$expectedVersion = (Get-Content windows/package.json | ConvertFrom-Json).version
$server = Start-Process node -ArgumentList @('windows/scripts/update-test-server.js','windows/dist/installer', $portFile) -PassThru
try {
  for ($i=0; $i -lt 30 -and !(Test-Path $portFile); $i++) { Start-Sleep 1 }
  $port = Get-Content $portFile
  $env:FISHTOUCHING_UPDATE_TEST_URL = "http://127.0.0.1:$port/"
  $oldProcess = Start-Process (Join-Path $installed 'FishTouching Reader.exe') -PassThru
  $failed = Join-Path $library 'upgrade-failed.txt'
  $restarted = $null
  for ($i=0; $i -lt 180 -and !(Test-Path $failed); $i++) {
    Start-Sleep 1
    $actual = Get-Content "$installed/resources/app/package.json" -ErrorAction SilentlyContinue | ConvertFrom-Json
    if ($actual.version -eq $expectedVersion -and $actual.main -eq 'main.js') {
      $restarted = Get-CimInstance Win32_Process -Filter "Name='FishTouching Reader.exe'" | Where-Object { $_.ExecutablePath -eq "$installed\FishTouching Reader.exe" -and $_.ProcessId -ne $oldProcess.Id -and $_.CommandLine -match '--updated' -and $_.CommandLine -notmatch '--type=' } | Select-Object -First 1
      if ($restarted) { break }
    }
  }
  Get-Content "$library/upgrade-dialogs.txt" -ErrorAction SilentlyContinue
  Get-Content "$library/upgrade-errors.txt" -ErrorAction SilentlyContinue
  if (Test-Path $failed) { throw (Get-Content $failed -Raw) }
  if (!$restarted) { throw 'Production app did not automatically relaunch after replacement' }
  if (!(Test-Path "$library/upgrade-download-ok.txt")) { throw 'Updater download was not exercised' }
  Start-Sleep 3
  if (!(Get-Process -Id $restarted.ProcessId -ErrorAction SilentlyContinue)) { throw 'Restarted app exited unexpectedly' }
  & node windows/scripts/update-verify-library.js "$installed/resources/app" $library $expectedVersion
  if ($LASTEXITCODE -ne 0) { throw 'Library retention verification failed' }
  Write-Output "Actual NSIS download, replacement, automatic relaunch PID $($restarted.ProcessId) and library retention passed"
} finally {
  Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
  Get-Process 'FishTouching Reader' -ErrorAction SilentlyContinue | Where-Object { $_.Path.StartsWith($root) } | Stop-Process -Force
  Remove-Item Env:FISHTOUCHING_UPDATE_TEST_URL -ErrorAction SilentlyContinue
  Remove-Item Env:FTR_UPGRADE_TEST_ROOT -ErrorAction SilentlyContinue
}
