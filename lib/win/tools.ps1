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
  # -1978335189 (0x8A15002B): nothing to upgrade, so it is already installed.
  if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
    Update-SessionPath
    Ok "installed $label"
    return $true
  }
  if ($LASTEXITCODE -eq -1978335226) {
    # 0x8A150006: winget couldn't launch the installer (admin approval declined, or blocked).
    Warn "$label: Windows didn't let the installer start. If a permission prompt appeared, choose Yes."
    Warn "Otherwise open PowerShell with 'Run as administrator' and run: winget install --exact --id $id"
  } else {
    Warn "$label install failed (winget exit code $LASTEXITCODE). Try: winget install --exact --id $id"
  }
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
  # The native installer puts claude in %USERPROFILE%\.local\bin. Make sure that folder is on PATH
  # (now and for new terminals) whether we install claude or it was already there.
  $claudeBin = Join-Path $env:USERPROFILE '.local\bin'
  if (-not (Has claude) -and -not (Test-Path (Join-Path $claudeBin 'claude.exe'))) {
    # Run the vendor script in its own PowerShell so an `exit` in it can't end ranch. Its output stays visible.
    $ps = (Get-Process -Id $PID).Path
    & $ps -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
  }
  if (Test-Path (Join-Path $claudeBin 'claude.exe')) { Add-UserPath $claudeBin }
  Update-SessionPath
  if (Has claude) { Ok "claude ready" } else { Warn "Claude Code isn't available. Run 'irm https://claude.ai/install.ps1 | iex' to see why." }

  if (Has codex) {
    Ok "codex already present"
  } elseif (Has npm) {
    & npm install -g '@openai/codex@latest'
    $npmBin = Join-Path $env:APPDATA 'npm'
    if (Test-Path $npmBin) { Add-UserPath $npmBin }
    Update-SessionPath
    if (Has codex) { Ok "installed codex" } else { Warn "Codex install failed; see the npm output above." }
  } else {
    Warn "Codex needs Node (npm), which isn't available yet. Open a new PowerShell window and run ranch again."
  }
}
