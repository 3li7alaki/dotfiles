#!/usr/bin/env bash
# Install jq through the native package manager on macOS and common Linux families.
set -euo pipefail

command -v jq >/dev/null 2>&1 && exit 0

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else printf 'error: installing jq requires root or sudo\n' >&2; exit 1
  fi
}

case "$(uname -s)" in
  Darwin)
    command -v brew >/dev/null 2>&1 || {
      printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
      exit 1
    }
    brew install jq
    ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then as_root apt-get install -y jq
    elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y jq
    elif command -v yum >/dev/null 2>&1; then as_root yum install -y jq
    elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm jq
    elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install jq
    elif command -v apk >/dev/null 2>&1; then as_root apk add jq
    elif command -v xbps-install >/dev/null 2>&1; then as_root xbps-install -Sy jq
    else
      printf 'error: no supported package manager found; see https://jqlang.org/download/\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'error: unsupported OS; see https://jqlang.org/download/\n' >&2
    exit 1
    ;;
esac

command -v jq >/dev/null 2>&1 || {
  printf 'error: jq installation completed but jq is not on PATH\n' >&2
  exit 1
}
