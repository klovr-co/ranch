# T3 Code on Windows: runs in the background; the T3 app on your main computer controls it over Tailscale.
# Skip it with RANCH_T3=0. Pick the release train with RANCH_T3_CHANNEL=stable|nightly.

function Test-T3Wanted { $env:RANCH_T3 -ne '0' }

function Get-T3Channel {
  if ($env:RANCH_T3_CHANNEL) { return $env:RANCH_T3_CHANNEL }
  if ((Has t3) -and ((Run-Quiet t3 --version) -match 'nightly')) { return 'nightly' }
  return 'stable'
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

  # T3's background service only exists on Linux (systemd) and macOS (launchd), so on Windows
  # it has to be started by hand until we add a logon task.
  Info "T3 can't run as a background service on Windows yet. Start it with: t3"
}

function Login-T3 {
  if (-not (Test-T3Wanted)) { return }
  if (-not (Has t3)) { Info "  T3 Code      not installed"; return }
  $sessions = Run-Quiet t3 auth session list
  $n = @($sessions -split "`n" | Where-Object { $_ -match '^  client:' }).Count
  if ($n -gt 0) { Ok "T3 Code      $n device(s) paired" }
  else { Warn "T3 Code      no devices paired (run: ranch pair)" }
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
