# Logins: show what's signed in, walk through what isn't.
# Every flow prints a link + code, so a machine with no screen can be approved from a phone or another computer.

# Under `curl | bash`, stdin is the script itself; interactive steps must read the real terminal.
can_prompt() { [ -t 1 ] && { : </dev/tty; } 2>/dev/null; }

gh_cmd() { "$MISE" exec -- gh "$@"; }

login_github() {
  if gh_cmd auth status >/dev/null 2>&1; then
    ok "GitHub       $(gh_cmd api user --jq .login 2>/dev/null)"
  elif [ "${1:-}" = run ]; then
    info "→ GitHub: open the link and enter the code"
    gh_cmd auth login --hostname github.com --git-protocol https --web </dev/tty || warn "GitHub login skipped"
    login_github status
  else
    warn "GitHub       not signed in"
  fi
}

login_claude() {
  if ! has claude; then warn "Claude Code  not installed"; return; fi
  if claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
    ok "Claude Code  $(claude auth status 2>/dev/null | sed -n 's/.*"email": *"\([^"]*\)".*/\1/p')"
  elif [ "${1:-}" = run ]; then
    info "→ Claude Code: open the link and approve"
    claude auth login </dev/tty || warn "Claude login skipped"
    login_claude status
  else
    warn "Claude Code  not signed in"
  fi
}

login_codex() {
  if ! has codex; then warn "Codex        not installed"; return; fi
  if codex login status 2>&1 | grep -qi '^logged in'; then
    ok "Codex        $(codex login status 2>&1 | head -1)"
  elif [ "${1:-}" = run ]; then
    info "→ Codex: open the link and enter the code"
    codex login --device-auth </dev/tty || warn "Codex login skipped"
    login_codex status
  else
    warn "Codex        not signed in"
  fi
}

# The secret manager is installed in its own step; until then just report.
login_secrets() {
  if has infisical; then ok "Infisical    installed"; else info "· Secrets      not set up yet"; fi
}

# setup login        → sign in to anything missing
# setup login status → only report
run_logins() {
  local mode="${1:-run}"
  step "Logins"
  if [ "$mode" = run ] && ! can_prompt; then
    warn "No terminal to ask on; run 'setup login' yourself to sign in."
    mode=status
  fi
  login_github "$mode"
  login_tailscale "$mode"
  login_secrets
  login_claude "$mode"
  login_codex "$mode"
}
