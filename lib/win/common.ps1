# Shared helpers for ranch on Windows. ASCII only; works in PowerShell 5.1 and 7.

function Step($m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor White }
function Info($m) { Write-Host "    $m" }
function Ok($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "error: $m" -ForegroundColor Red; exit 1 }

function Has($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# Installers update the registry PATH, not this session's. Re-read it so new tools are found right away.
function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = (($machine, $user) | Where-Object { $_ }) -join ';'
}

# Add a folder to the user's PATH once (and to this session).
function Add-UserPath($dir) {
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @()
  if ($user) { $parts = $user -split ';' | Where-Object { $_ } }
  if ($parts -notcontains $dir) {
    [Environment]::SetEnvironmentVariable('Path', (($parts + $dir) -join ';'), 'User')
    Ok "added $dir to your PATH"
  }
  Update-SessionPath
}

# Is there a person at a terminal who can answer prompts?
function Can-Prompt {
  [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

# Run a native command, return its output as one string (stderr dropped), and set $global:LASTEXITCODE.
function Run-Quiet {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $args[0] @($args | Select-Object -Skip 1) 2>$null | Out-String
  } catch { $out = '' }
  $ErrorActionPreference = $old
  return $out.Trim()
}
