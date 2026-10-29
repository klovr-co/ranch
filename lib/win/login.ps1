# Logins on Windows: show what's signed in, walk through what isn't.

function Login-GitHub($mode) {
  if (-not (Has gh)) { Warn "GitHub       gh not installed"; return }
  $null = Run-Quiet gh auth status
  if ($LASTEXITCODE -eq 0) { Ok "GitHub       $(Run-Quiet gh api user --jq .login)"; return }
  if ($mode -ne 'run') { Warn "GitHub       not signed in"; return }
  Info "-> GitHub: open the link and enter the code"
  & gh auth login --hostname github.com --git-protocol https --web
  if ($LASTEXITCODE -ne 0) { Warn "GitHub login skipped"; return }
  Login-GitHub 'status'
}

function Login-Claude($mode) {
  if (-not (Has claude)) { Warn "Claude Code  not installed"; return }
  $st = Run-Quiet claude auth status
  if ($st -match '"loggedIn":\s*true') {
    $email = ''
    if ($st -match '"email":\s*"([^"]*)"') { $email = $Matches[1] }
    Ok "Claude Code  $email"; return
  }
  if ($mode -ne 'run') { Warn "Claude Code  not signed in"; return }
  Info "-> Claude Code: open the link and approve"
  & claude auth login
  if ($LASTEXITCODE -ne 0) { Warn "Claude login skipped"; return }
  Login-Claude 'status'
}

function Login-Codex($mode) {
  if (-not (Has codex)) { Warn "Codex        not installed"; return }
  $st = Run-Quiet codex login status
  if ($st -match '(?im)^logged in') { Ok "Codex        $(($st -split "`n")[0].Trim())"; return }
  if ($mode -ne 'run') { Warn "Codex        not signed in"; return }
  Info "-> Codex: open the link below and enter the code"
  & codex login --device-auth
  if ($LASTEXITCODE -ne 0) { Warn "Codex login skipped"; return }
  Login-Codex 'status'
}

function Login-Gcloud($mode) {
  if (-not (Has gcloud)) { Info "  Google Cloud gcloud not installed"; return }
  $acct = Run-Quiet gcloud auth list '--filter=status:ACTIVE' '--format=value(account)'
  if ($acct) { Ok "Google Cloud $(($acct -split "`n")[0].Trim())"; return }
  if ($mode -ne 'run') { Warn "Google Cloud not signed in"; return }
  Info "-> Google Cloud: sign in in the browser"
  & gcloud auth login
  if ($LASTEXITCODE -ne 0) { Warn "Google Cloud login skipped"; return }
  Login-Gcloud 'status'
}

# ranch login        -> sign in to anything missing
# ranch login status -> only report
function Invoke-Logins($mode) {
  Step "Logins"
  if ($mode -eq 'run' -and -not (Can-Prompt)) {
    Warn "No terminal to ask on; run 'ranch login' yourself to sign in."
    $mode = 'status'
  }
  Login-GitHub $mode
  Login-Tailscale $mode
  Login-Gcloud $mode
  Login-Claude $mode
  Login-Codex $mode
}
