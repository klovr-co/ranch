# Tools: mise for pinned versions, plus the agent CLIs.

MISE="$HOME/.local/bin/mise"

install_mise() {
  step "mise (tool versions)"
  if [ -x "$MISE" ]; then
    "$MISE" self-update --yes >/dev/null 2>&1 || true
    ok "mise $("$MISE" --version | awk '{print $1}')"
  else
    curl -fsSL https://mise.run | sh >/dev/null 2>&1 || die "mise install failed (see https://mise.jdx.dev)"
    ok "installed mise"
  fi
  local shell_name rc
  shell_name="$(basename "${SHELL:-bash}")"
  case "$shell_name" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)    warn "Unknown shell $shell_name; add mise activation yourself"; return ;;
  esac
  append_once "$rc" "eval \"\$($MISE activate $shell_name)\""
  ok "mise activated in $rc"
  export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
}

# Base tools every machine gets, independent of team.
install_base_tools() {
  step "Base tools"
  "$MISE" --quiet use --global --yes gh@latest >/dev/null
  ok "gh $("$MISE" exec -- gh --version | head -1 | awk '{print $3}')"
  # Node is needed for the agent CLIs. Keep any Node the user already has on PATH.
  if ! has node; then
    "$MISE" --quiet use --global --yes node@lts >/dev/null
    ok "node (lts)"
  else
    ok "node $(node --version) already present"
  fi
}

install_agent_clis() {
  step "Agent CLIs"
  if has claude; then
    ok "claude $(claude --version 2>/dev/null | awk '{print $1}') already present"
  else
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null
    ok "installed claude (native installer)"
  fi
  if has codex; then
    ok "codex already present"
  else
    "$MISE" --quiet use --global --yes npm:@openai/codex@latest >/dev/null
    ok "installed codex"
  fi
}
