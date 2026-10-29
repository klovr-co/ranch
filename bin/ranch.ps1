# ranch for Windows: add this machine to your ranch.
# Safe to re-run: it only changes what's different.
# Supported here: setup/update, login, login status, doctor. Everything else says so and exits.
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.

$ErrorActionPreference = 'Continue'
$ROOT = Split-Path -Parent $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

. (Join-Path $ROOT 'lib\win\common.ps1')
. (Join-Path $ROOT 'lib\win\tools.ps1')
. (Join-Path $ROOT 'lib\win\network.ps1')
. (Join-Path $ROOT 'lib\win\login.ps1')
. (Join-Path $ROOT 'lib\win\t3.ps1')

$RanchHome = Join-Path $env:LOCALAPPDATA 'ranch'

function Show-Usage {
  @'
ranch for Windows - add this machine to your ranch

  ranch                       Install or update everything
  ranch login                 Sign in to anything missing (GitHub, Tailscale, Google Cloud, Claude Code, Codex)
  ranch login status          Only show what's signed in
  ranch doctor                Show what's installed
  ranch --no-login            Install or update, skip the sign-ins

  ranch t3                    Install or update only T3 Code and start it
  ranch pair                  Pair T3 Code on this machine with the T3 app on your main computer

Not on Windows yet: --team, status, update, run, secrets, join, add.
Safe to re-run any time.
'@ | Write-Host
}

function Test-Unsupported($cmd) {
  Write-Host "error: 'ranch $cmd' isn't available on Windows yet." -ForegroundColor Red
  Write-Host "    On Windows ranch can set up this machine: ranch, ranch login, ranch doctor."
  exit 1
}

# The installed copy keeps itself current; a dev checkout is left alone.
function Update-Self($ranchArgs) {
  if ($ROOT -ne $RanchHome -or -not (Test-Path (Join-Path $ROOT '.git')) -or -not (Has git)) { return }
  if ($env:RANCH_UPDATED) { return }
  $before = (& git -C $ROOT rev-parse HEAD)
  & git -C $ROOT pull --ff-only --quiet 2>$null
  if ($LASTEXITCODE -ne 0) { Warn "Couldn't update ranch; using the current version"; return }
  $after = (& git -C $ROOT rev-parse HEAD)
  if ($before -ne $after) {
    Info "ranch updated; restarting"
    $env:RANCH_UPDATED = '1'
    $ps = (Get-Process -Id $PID).Path
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ROOT 'bin\ranch.ps1') @ranchArgs
    exit $LASTEXITCODE
  }
}

# A snapshot install (made before git existed) becomes a clone once git is installed.
function Convert-ToClone {
  if ($ROOT -ne $RanchHome -or (Test-Path (Join-Path $ROOT '.git')) -or -not (Has git)) { return }
  $repo = if ($env:RANCH_REPO) { $env:RANCH_REPO } else { 'https://github.com/klovr-co/ranch.git' }
  & git -C $ROOT init -q
  & git -C $ROOT remote add origin $repo
  $branch = if ($env:RANCH_BRANCH) { $env:RANCH_BRANCH } else { 'main' }
  & git -C $ROOT fetch -q origin $branch
  if ($LASTEXITCODE -eq 0) {
    & git -C $ROOT reset -q --hard FETCH_HEAD
    & git -C $ROOT checkout -q -B $branch FETCH_HEAD 2>$null
    & git -C $ROOT branch -q -u "origin/$branch" 2>$null
  }
}

# Put `ranch` on PATH (bin\ranch.cmd runs this script).
function Install-Command { Add-UserPath (Join-Path $ROOT 'bin') }

function Invoke-Doctor {
  Step "Machine: $([Environment]::OSVersion.VersionString) ($env:PROCESSOR_ARCHITECTURE)"
  foreach ($t in 'winget', 'git', 'gh', 'gcloud', 'uv', 'node', 'pnpm', 'claude', 'codex') {
    if (Has $t) { Ok $t } else { Warn "$t missing" }
  }
  if (Get-TailscaleBin) { Ok 'tailscale' } else { Warn 'tailscale missing' }
  if (Test-T3Wanted) { if (Has t3) { Ok 't3' } else { Warn 't3 missing' } }
}

$logins = $true
$i = 0
$a = @($args)
while ($i -lt $a.Count) {
  switch -Regex ($a[$i]) {
    '^(-h|--help|help)$' { Show-Usage; exit 0 }
    '^doctor$' { Invoke-Doctor; exit 0 }
    '^login$' {
      if ($i + 1 -lt $a.Count -and $a[$i + 1] -eq 'status') { Invoke-Logins 'status' } else { Invoke-Logins 'run' }
      exit 0
    }
    '^--no-login$' { $logins = $false }
    '^t3$' { Install-T3; exit 0 }
    '^pair$' {
      if ($i + 1 -lt $a.Count) { Test-Unsupported "pair $($a[$i + 1])" }
      Invoke-PairT3; exit 0
    }
    '^(status|update|run|secrets|join|add|--team.*)$' { Test-Unsupported $a[$i] }
    default { Die "Unknown argument: $($a[$i]) (try --help)" }
  }
  $i++
}

Update-Self $a
Step "Machine: $([Environment]::OSVersion.VersionString) ($env:PROCESSOR_ARCHITECTURE)"
Install-BaseTools
Convert-ToClone
Install-AgentClis
Install-Tailscale
Install-T3
Install-Command
if ($logins) { Invoke-Logins 'run' }

Step "Done"
$missing = @('git','gh','claude','codex') | Where-Object { -not (Has $_) }
if ($missing) { Warn "Not found yet: $($missing -join ', '). Open a NEW PowerShell window and run 'ranch doctor'." }
Info "This machine is on the ranch. Open a new PowerShell window so every tool is on your PATH, then run 'ranch doctor' any time."
