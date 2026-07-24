#!/usr/bin/env bash
# Install fzf and expose the repo-owned cross-version shell initializer.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_BIN="$HOME/.local/bin"

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else printf 'error: installing fzf requires root or sudo\n' >&2; exit 1
  fi
}

if ! command -v fzf >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin)
      command -v brew >/dev/null 2>&1 || {
        printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
        exit 1
      }
      brew install fzf
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then as_root apt-get install -y fzf
      elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y fzf
      elif command -v yum >/dev/null 2>&1; then as_root yum install -y fzf
      elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm fzf
      elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install fzf
      elif command -v apk >/dev/null 2>&1; then as_root apk add fzf
      elif command -v xbps-install >/dev/null 2>&1; then as_root xbps-install -Sy fzf
      else
        printf 'error: no supported package manager found; see https://github.com/junegunn/fzf#installation\n' >&2
        exit 1
      fi
      ;;
    *)
      printf 'error: unsupported OS; see https://github.com/junegunn/fzf#installation\n' >&2
      exit 1
      ;;
  esac
fi

command -v fzf >/dev/null 2>&1 || {
  printf 'error: fzf installation completed but fzf is not on PATH\n' >&2
  exit 1
}

mkdir -p "$LOCAL_BIN"
ln -sfn "$DOTFILES/scripts/fzf-shell-init" "$LOCAL_BIN/fzf-shell-init"
