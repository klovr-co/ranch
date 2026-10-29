# One-line installer for Windows 11 (PowerShell 5.1 or 7):
#   irm klovr-co.github.io/ranch/install.ps1 | iex
# With arguments (login, doctor, ...):
#   & ([scriptblock]::Create((irm klovr-co.github.io/ranch/install.ps1))) login
# Fetches this repo into %LOCALAPPDATA%\ranch, then runs bin\ranch.ps1 with the same arguments.
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow in 5.1 with the progress bar

$RanchRepo = if ($env:RANCH_REPO) { $env:RANCH_REPO } else { 'https://github.com/klovr-co/ranch.git' }
$RanchBranch = if ($env:RANCH_BRANCH) { $env:RANCH_BRANCH } else { 'main' }   # test a branch: $env:RANCH_BRANCH = 'my-branch'
$RanchZip  = if ($env:RANCH_ZIP)  { $env:RANCH_ZIP }  else { "https://codeload.github.com/klovr-co/ranch/zip/refs/heads/$RanchBranch" }
$RanchHome = if ($env:RANCH_HOME) { $env:RANCH_HOME } else { Join-Path $env:LOCALAPPDATA 'ranch' }

# Windows' default execution policy blocks .ps1 files, so run ranch with a process-only bypass.
# Nothing about the machine's policy is changed.
function Start-Ranch($root, $ranchArgs) {
  $ps = (Get-Process -Id $PID).Path
  & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'bin\ranch.ps1') @ranchArgs
  exit $LASTEXITCODE
}

if ($env:RANCH_SOURCE_DIR) {
  # Local testing: run straight from a checkout.
  Start-Ranch $env:RANCH_SOURCE_DIR $args
}

$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
if ((Test-Path (Join-Path $RanchHome '.git')) -and $hasGit) {
  git -C $RanchHome pull --ff-only --quiet
} elseif ($hasGit) {
  if (Test-Path $RanchHome) { Remove-Item -Recurse -Force $RanchHome }
  git clone --quiet --branch $RanchBranch $RanchRepo $RanchHome
} else {
  # No git yet: fetch a snapshot. ranch installs git and switches to a clone later.
  $tmp = Join-Path $env:TEMP ('ranch-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Invoke-WebRequest -UseBasicParsing -Uri $RanchZip -OutFile (Join-Path $tmp 'ranch.zip')
  Expand-Archive -Path (Join-Path $tmp 'ranch.zip') -DestinationPath $tmp -Force
  if (Test-Path $RanchHome) { Remove-Item -Recurse -Force $RanchHome }
  $extracted = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
  Move-Item -Path $extracted.FullName -Destination $RanchHome
  Remove-Item -Recurse -Force $tmp
}

Start-Ranch $RanchHome $args
