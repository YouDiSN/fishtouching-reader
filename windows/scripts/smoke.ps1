param(
  [Parameter(Mandatory = $true)][string]$Executable,
  [Parameter(Mandatory = $true)][string[]]$AppArguments
)
$ErrorActionPreference = 'Stop'
$ok = Join-Path $env:FISHTOUCHING_SMOKE_ROOT 'smoke-ok.txt'
$out = Join-Path $env:RUNNER_TEMP "electron-smoke-$([guid]::NewGuid()).out"
$err = Join-Path $env:RUNNER_TEMP "electron-smoke-$([guid]::NewGuid()).err"
$exe = (Resolve-Path $Executable).Path
$process = Start-Process -FilePath $exe -ArgumentList $AppArguments -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
try {
  for ($i = 0; $i -lt 90 -and !(Test-Path $ok) -and !$process.HasExited; $i++) { Start-Sleep -Seconds 1 }
  Get-Content $out -ErrorAction SilentlyContinue
  Get-Content $err -ErrorAction SilentlyContinue
  if (!(Test-Path $ok)) { throw "Electron smoke did not complete: $exe" }
  Write-Output (Get-Content $ok)
} finally {
  if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
}
