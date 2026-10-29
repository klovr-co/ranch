# T3 Code on Windows: runs in the background; the T3 app on your main computer controls it over Tailscale.
# T3 has no Windows background service, so ranch starts `t3 serve` at sign-in instead (Scheduled Task,
# or a Startup shortcut if Windows won't allow the task). Skip T3 with RANCH_T3=0. Pick the release train with RANCH_T3_CHANNEL=stable|nightly.

function Test-T3Wanted { $env:RANCH_T3 -ne '0' }

function Get-T3Channel {
  if ($env:RANCH_T3_CHANNEL) { return $env:RANCH_T3_CHANNEL }
  if ((Has t3) -and ((Run-Quiet t3 --version) -match 'nightly')) { return 'nightly' }
  return 'stable'
}

$T3TaskName = 'ranch-t3'
$T3Port = 3773

function Test-T3Running { [bool](Get-NetTCPConnection -LocalPort $T3Port -State Listen -ErrorAction SilentlyContinue) }

# The PowerShell arguments that run the T3 server hidden. Expose it on the tailnet only when Tailscale is connected,
# otherwise `t3 serve --tailscale-serve` would fail at sign-in.
function Get-T3ServeArgs {
  $t3 = (Get-Command t3).Source
  $serve = 'serve'
  $ts = Get-TailscaleBin
  if ($ts) { $null = Run-Quiet $ts status; if ($LASTEXITCODE -eq 0) { $serve = 'serve --tailscale-serve' } }
  return "-NoProfile -WindowStyle Hidden -Command `"& '$t3' $serve`""
}

# Start T3 at sign-in. Returns 'task', 'startup' or '' (neither worked).
function Register-T3Startup($psArgs) {
  try {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs -WorkingDirectory $env:USERPROFILE
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
      -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
    Register-ScheduledTask -TaskName $T3TaskName -Action $action -Trigger $trigger -Settings $settings -Force -ErrorAction Stop | Out-Null
    return 'task'
  } catch {
    try {
      $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'ranch-t3.lnk'
      $sh = New-Object -ComObject WScript.Shell
      $sc = $sh.CreateShortcut($lnk)
      $sc.TargetPath = 'powershell.exe'
      $sc.Arguments = $psArgs
      $sc.WorkingDirectory = $env:USERPROFILE
      $sc.WindowStyle = 7
      $sc.Save()
      return 'startup'
    } catch { return '' }
  }
}

function Install-T3 {
  if (-not (Test-T3Wanted)) { return }
  Step "T3 Code (control agents from your other devices)"
  $channel = Get-T3Channel
  # T3's own installer follows T3CODE_CHANNEL and also updates an existing install.
  # Run it in its own PowerShell so an `exit` in it can't end ranch. Its output stays visible.
  $env:T3CODE_CHANNEL = $channel
  $ps = (Get-Process -Id $PID).Path
  & $ps -NoProfile -ExecutionPolicy Bypass -Command "irm https://t3.codes/install.ps1 | iex"
  $bin = Join-Path $env:USERPROFILE '.local\bin'
  if (Test-Path (Join-Path $bin 't3.cmd')) { Add-UserPath $bin }
  Update-SessionPath
  if (-not (Has t3)) { Warn "T3 install failed; skipping"; return }
  Ok "t3 $(Run-Quiet t3 --version) ($channel)"

  # T3's own background service only exists on Linux (systemd) and macOS (launchd), so start `t3 serve` at sign-in.
  $psArgs = Get-T3ServeArgs
  $how = Register-T3Startup $psArgs
  if (-not (Test-T3Running)) {
    Start-Process powershell.exe -ArgumentList $psArgs -WindowStyle Hidden
    Start-Sleep -Seconds 6
  }
  if (Test-T3Running) { Ok "T3 running in the background (starts again when you sign in)" }
  else { Warn "T3 didn't start. Run 't3 serve' to see why." }
  if (-not $how) { Warn "Couldn't set T3 to start at sign-in; run 'ranch' again after signing in, or start it with 't3 serve'." }
}

function Login-T3 {
  if (-not (Test-T3Wanted)) { return }
  if (-not (Has t3)) { Info "  T3 Code      not installed"; return }
  $sessions = Run-Quiet t3 auth session list
  $n = @($sessions -split "`n" | Where-Object { $_ -match '^  client:' }).Count
  if ($n -gt 0) { Ok "T3 Code      running, $n device(s) paired" }
  elseif (Test-T3Running) { Warn "T3 Code      running, no devices paired (run: ranch pair)" }
  else { Warn "T3 Code      not running (start it with: t3 serve, or run ranch)" }
}

# Pair this machine's T3 with the T3 app on your main computer. Run it here, then paste the link there.
function Invoke-PairT3 {
  if (-not (Test-T3Wanted)) { Info "T3 is turned off (RANCH_T3=0)."; return }
  if (-not (Has t3)) { Die "T3 isn't installed. Run: ranch" }
  Step "Pair T3 Code with your main computer"
  $out = & t3 pair --tailscale --label $env:COMPUTERNAME --ttl 30m 2>&1 | Out-String
  if ($out -match '(https://\S+/pair#token=[A-Za-z0-9]+)') {
    $url = $Matches[1]
    try { Set-Clipboard -Value $url; Ok "pairing link copied (valid 30 min)" } catch { Ok "pairing link ready (valid 30 min)" }
    Info "On your main computer, open T3 Code: Settings -> Connections -> Add environment, and paste this:"
    Info $url
    return
  }
  # First time on a Tailscale account, private HTTPS must be switched on once.
  $serve = & tailscale serve --https=443 --bg http://127.0.0.1:3773 2>&1 | Out-String
  if ($serve -match '(https://login\.tailscale\.com/f/serve\S*)') {
    Info "Tailscale needs a one-time approval for private HTTPS addresses (once per account). Open this, approve, then run: ranch pair"
    Info $Matches[1]
  } else {
    Warn "Couldn't create a pairing link. Is Tailscale connected (ranch login)? Output:"
    Info $out.Trim()
  }
}
