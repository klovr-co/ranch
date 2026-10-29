# Tools on Windows: winget for the base tools, the vendors' own installers for Claude Code and Codex.

function Test-Winget {
  if (-not (Has winget)) {
    Die "winget not found. Open the Microsoft Store, update 'App Installer', then run ranch again."
  }
}

# Install one winget package if it isn't there yet. Returns $true when it is installed afterwards.
function Install-WingetPackage($id, $label) {
  $null = Run-Quiet winget list --id $id --exact --accept-source-agreements
  if ($LASTEXITCODE -eq 0) { Ok "$label already installed"; return $true }
  Info "Installing $label (a Windows permission prompt may appear)..."
  & winget install --exact --id $id --silent --accept-package-agreements --accept-source-agreements | Out-Null
  # -1978335189 (0x8A150011): already installed, nothing to upgrade.
  if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
    Update-SessionPath
    Ok "installed $label"
    return $true
  }
  Warn "$label install failed (winget exit code $LASTEXITCODE)"
  return $false
}

function Install-BaseTools {
  Step "Base tools (winget)"
  Test-Winget
  $null = Install-WingetPackage 'Git.Git' 'git'
  $null = Install-WingetPackage 'GitHub.cli' 'gh'
  $null = Install-WingetPackage 'astral-sh.uv' 'uv'
  $null = Install-WingetPackage 'Google.CloudSDK' 'gcloud'
  # Node is needed for Codex. Keep any Node already on PATH.
  if (Has node) { Ok "node $(node --version) already present" }
  else { $null = Install-WingetPackage 'OpenJS.NodeJS.LTS' 'node (lts)' }
  if ((Has npm) -and -not (Has pnpm)) {
    & npm install -g pnpm 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "installed pnpm" } else { Warn "pnpm install failed" }
  } elseif (Has pnpm) { Ok "pnpm already present" }
}

function Install-AgentClis {
  Step "Agent CLIs"
  if (Has claude) {
    Ok "claude already present"
  } else {
    # Run the vendor script in its own PowerShell so an `exit` in it can't end ranch.
    $ps = (Get-Process -Id $PID).Path
    & $ps -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex" | Out-Null
    # The native installer puts claude in %USERPROFILE%\.local\bin.
    $bin = Join-Path $env:USERPROFILE '.local\bin'
    if (Test-Path (Join-Path $bin 'claude.exe')) { Add-UserPath $bin }
    Update-SessionPath
    if (Has claude) { Ok "installed claude (native installer)" } else { Warn "Claude Code install failed; see https://code.claude.com/docs/en/setup" }
  }
  if (Has codex) {
    Ok "codex already present"
  } elseif (Has npm) {
    & npm install -g '@openai/codex@latest' 2>&1 | Out-Null
    Update-SessionPath
    $npmBin = Join-Path $env:APPDATA 'npm'
    if ((Test-Path $npmBin) -and -not (Has codex)) { Add-UserPath $npmBin }
    if (Has codex) { Ok "installed codex" } else { Warn "Codex install failed. Run 'npm install -g @openai/codex' to see why." }
  } else {
    Warn "Codex needs Node (npm), which isn't available yet. Open a new terminal and run ranch again."
  }
}
