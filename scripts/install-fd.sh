#!/usr/bin/env bash
# Install sharkdp/fd and normalize Debian's `fdfind` binary to `~/.local/bin/fd`.
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"

is_sharkdp_fd() {
  command -v fd >/dev/null 2>&1 && fd --version 2>/dev/null | grep -Eq '^fd [0-9]'
}

is_sharkdp_fd && exit 0

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else printf 'error: installing fd requires root or sudo\n' >&2; exit 1
  fi
}

case "$(uname -s)" in
  Darwin)
    command -v brew >/dev/null 2>&1 || {
      printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
      exit 1
    }
    brew install fd
    ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      as_root apt-get install -y fd-find
      command -v fdfind >/dev/null 2>&1 || {
        printf 'error: fd-find installed without an fdfind binary\n' >&2
        exit 1
      }
      mkdir -p "$LOCAL_BIN"
      ln -sfn "$(command -v fdfind)" "$LOCAL_BIN/fd"
    elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y fd-find
    elif command -v yum >/dev/null 2>&1; then as_root yum install -y fd-find
    elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm fd
    elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install fd
    elif command -v apk >/dev/null 2>&1; then as_root apk add fd
    elif command -v xbps-install >/dev/null 2>&1; then as_root xbps-install -Sy fd
    else
      printf 'error: no supported package manager found; install from https://github.com/sharkdp/fd/releases\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'error: unsupported OS; install fd from https://github.com/sharkdp/fd/releases\n' >&2
    exit 1
    ;;
esac

is_sharkdp_fd || {
  printf 'error: fd installation completed but sharkdp/fd is not available as fd on PATH\n' >&2
  exit 1
}
