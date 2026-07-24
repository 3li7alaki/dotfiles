#!/usr/bin/env bash
# Install tmux through Homebrew or a common Linux package manager.
set -euo pipefail

command -v tmux >/dev/null 2>&1 && exit 0

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else printf 'error: installing tmux requires root or sudo\n' >&2; exit 1
  fi
}

case "$(uname -s)" in
  Darwin)
    command -v brew >/dev/null 2>&1 || {
      printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
      exit 1
    }
    brew install tmux
    ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then as_root apt-get install -y tmux
    elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y tmux
    elif command -v yum >/dev/null 2>&1; then as_root yum install -y tmux
    elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm tmux
    elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install tmux
    elif command -v apk >/dev/null 2>&1; then as_root apk add tmux
    elif command -v xbps-install >/dev/null 2>&1; then as_root xbps-install -Sy tmux
    else
      printf 'error: no supported package manager found; see https://github.com/tmux/tmux/wiki/Installing\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'error: unsupported OS; see https://github.com/tmux/tmux/wiki/Installing\n' >&2
    exit 1
    ;;
esac

command -v tmux >/dev/null 2>&1 || {
  printf 'error: tmux installation completed but tmux is not on PATH\n' >&2
  exit 1
}
