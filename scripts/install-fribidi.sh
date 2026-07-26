#!/usr/bin/env bash
# Install FriBidi (Unicode bidi algorithm CLI) and expose the repo-owned shell initializer.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_BIN="$HOME/.local/bin"

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else printf 'error: installing fribidi requires root or sudo\n' >&2; exit 1
  fi
}

if ! command -v fribidi >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin)
      command -v brew >/dev/null 2>&1 || {
        printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
        exit 1
      }
      brew install fribidi
      ;;
    Linux)
      # The CLI ships in the -bin/-utils split on some distros, the main package on others.
      if command -v apt-get >/dev/null 2>&1; then as_root apt-get install -y fribidi
      elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y fribidi
      elif command -v yum >/dev/null 2>&1; then as_root yum install -y fribidi
      elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm fribidi
      elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install fribidi
      elif command -v apk >/dev/null 2>&1; then as_root apk add fribidi
      elif command -v xbps-install >/dev/null 2>&1; then as_root xbps-install -Sy fribidi
      else
        printf 'error: no supported package manager found; see https://github.com/fribidi/fribidi\n' >&2
        exit 1
      fi
      ;;
    *)
      printf 'error: unsupported OS; see https://github.com/fribidi/fribidi\n' >&2
      exit 1
      ;;
  esac
fi

command -v fribidi >/dev/null 2>&1 || {
  printf 'error: fribidi installation completed but fribidi is not on PATH\n' >&2
  exit 1
}

mkdir -p "$LOCAL_BIN"
ln -sfn "$DOTFILES/scripts/bidi-shell-init" "$LOCAL_BIN/bidi-shell-init"
