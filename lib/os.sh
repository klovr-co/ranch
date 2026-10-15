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

install_base_packages() {
  step "Base packages ($OS_NAME)"
  case "$OS" in
    macos)
      xcode-select -p >/dev/null 2>&1 || die "Run: xcode-select --install   then re-run ranch."
      ok "Xcode command line tools present"
      ;;
    debian)
      sudo_cmd apt-get update -qq
      sudo_cmd apt-get install -y -qq git curl ca-certificates tmux build-essential unzip >/dev/null
      ok "git curl tmux build-essential"
      ;;
    fedora)
      sudo_cmd dnf install -y -q git curl ca-certificates tmux gcc gcc-c++ make unzip >/dev/null
      ok "git curl tmux gcc make"
      ;;
    arch)
      sudo_cmd pacman -Sy --needed --noconfirm git curl ca-certificates tmux base-devel unzip >/dev/null
      ok "git curl tmux base-devel"
      ;;
  esac
}
