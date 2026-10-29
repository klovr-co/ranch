# Tailscale on Windows: a private network between your machines.

function Get-TailscaleBin {
  $c = Get-Command tailscale -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($root in $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
    if (-not $root) { continue }
    $p = Join-Path $root 'Tailscale\tailscale.exe'
    if (Test-Path $p) { return $p }
  }
  return $null
}

function Install-Tailscale {
  Step "Tailscale (private network)"
  if (Get-TailscaleBin) { Ok "Tailscale installed"; return }
  $null = Install-WingetPackage 'Tailscale.Tailscale' 'Tailscale'
}

function Get-TailscaleHost($ts) {
  try { return ((Run-Quiet $ts status --json) | ConvertFrom-Json).Self.HostName } catch { return '' }
}

function Login-Tailscale($mode) {
  $ts = Get-TailscaleBin
  if (-not $ts) { Info "  Tailscale    not installed"; return }
  $null = Run-Quiet $ts status
  if ($LASTEXITCODE -eq 0) { Ok "Tailscale    connected as $(Get-TailscaleHost $ts)"; return }
  if ($mode -ne 'run') { Warn "Tailscale    not connected"; return }
  Info "-> Tailscale: open the link below and sign in. This window continues once you approve."
  & $ts up
  $null = Run-Quiet $ts status
  if ($LASTEXITCODE -eq 0) { Ok "Tailscale    connected as $(Get-TailscaleHost $ts)" } else { Warn "Tailscale login didn't finish" }
}
