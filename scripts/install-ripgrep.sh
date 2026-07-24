#!/usr/bin/env bash
# Install ripgrep through the native package manager on macOS and common Linux families.
set -euo pipefail

command -v rg >/dev/null 2>&1 && exit 0

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else printf 'error: installing ripgrep requires root or sudo\n' >&2; exit 1
  fi
}

case "$(uname -s)" in
  Darwin)
    command -v brew >/dev/null 2>&1 || {
      printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
      exit 1
    }
    brew install ripgrep
    ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then as_root apt-get install -y ripgrep
    elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y ripgrep
    elif command -v yum >/dev/null 2>&1; then as_root yum install -y ripgrep
    elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm ripgrep
    elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install ripgrep
    elif command -v apk >/dev/null 2>&1; then as_root apk add ripgrep
    elif command -v xbps-install >/dev/null 2>&1; then as_root xbps-install -Sy ripgrep
    else
      printf 'error: no supported package manager found; install from https://github.com/BurntSushi/ripgrep/releases\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'error: unsupported OS; install ripgrep from https://github.com/BurntSushi/ripgrep/releases\n' >&2
    exit 1
    ;;
esac

command -v rg >/dev/null 2>&1 || {
  printf 'error: ripgrep installation completed but rg is not on PATH\n' >&2
  exit 1
}
