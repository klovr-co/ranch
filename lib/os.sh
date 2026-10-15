# Detect the OS and install base packages. The only distro-aware part of ranch.

OS=""      # macos | debian | fedora | arch
OS_NAME=""

detect_os() {
  if [ "$(uname -s)" = "Darwin" ]; then
    OS=macos; OS_NAME="macOS $(sw_vers -productVersion)"
    return
  fi
  [ -r /etc/os-release ] || die "Unsupported system: no /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_NAME="${PRETTY_NAME:-$ID}"
  case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "*|*" ubuntu "*) OS=debian ;;
    *" fedora "*|*" rhel "*|*" centos "*) OS=fedora ;;
    *" arch "*) OS=arch ;;
    *) die "Unsupported Linux: $OS_NAME. Supported: Ubuntu, Debian, Fedora (Arch best effort)." ;;
  esac
  has systemctl || die "ranch needs systemd; $OS_NAME doesn't have it."
}

sudo_cmd() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

# Ask for the sudo password once, up front, with an explanation (sudo shows nothing while you type).
sudo_ready() {
  [ "$(id -u)" -eq 0 ] && return 0
  sudo -n true 2>/dev/null && return 0
  info "ranch needs your password to install system packages."
  info "Type it and press Enter. Nothing appears while you type; that's normal."
  if { : </dev/tty; } 2>/dev/null; then sudo -v </dev/tty; else sudo -v; fi
}

# Packages ranch needs that a fresh OS may not have, per package manager.
base_packages() {
  case "$OS" in
    debian) echo "git curl ca-certificates tmux build-essential unzip" ;;
    fedora) echo "git curl ca-certificates tmux gcc gcc-c++ make unzip" ;;
    arch)   echo "git curl ca-certificates tmux base-devel unzip" ;;
  esac
}

pkg_installed() {
  case "$OS" in
    debian) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    fedora) rpm -q "$1" >/dev/null 2>&1 ;;
    arch)   pacman -Qi "$1" >/dev/null 2>&1 || pacman -Qg "$1" >/dev/null 2>&1 ;;
  esac
}

install_base_packages() {
  step "Base packages ($OS_NAME)"
  if [ "$OS" = macos ]; then
    xcode-select -p >/dev/null 2>&1 || die "Run: xcode-select --install   then re-run ranch."
    ok "Xcode command line tools present"
    return
  fi

  # Only touch the package manager (and ask for a password) when something is missing.
  local p missing=""
  for p in $(base_packages); do pkg_installed "$p" || missing="$missing $p"; done
  if [ -z "$missing" ]; then
    ok "all present: $(base_packages)"
    return
  fi

  info "Missing:$missing"
  sudo_ready
  info "Installing them; this can take a few minutes on a fresh machine…"
  # shellcheck disable=SC2086
  case "$OS" in
    debian) sudo_cmd apt-get update -qq && sudo_cmd apt-get install -y -qq $missing >/dev/null ;;
    fedora) sudo_cmd dnf install -y -q $missing >/dev/null ;;
    arch)   sudo_cmd pacman -Sy --needed --noconfirm $missing >/dev/null ;;
  esac
  ok "installed:$missing"
}
