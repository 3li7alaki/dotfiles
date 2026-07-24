#!/usr/bin/env bash
# Install the official GitHub CLI while leaving account authentication user-owned.
set -euo pipefail

command -v gh >/dev/null 2>&1 && exit 0

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else printf 'error: installing GitHub CLI requires root or sudo\n' >&2; exit 1
  fi
}

case "$(uname -s)" in
  Darwin)
    command -v brew >/dev/null 2>&1 || {
      printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
      exit 1
    }
    brew install gh
    ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      tmp=$(mktemp "${TMPDIR:-/tmp}/github-cli-keyring.XXXXXX")
      trap 'rm -f "$tmp"' EXIT
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$tmp"
      as_root install -D -m 0644 "$tmp" /etc/apt/keyrings/githubcli-archive-keyring.gpg
      repo="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
      printf '%s\n' "$repo" | as_root tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      as_root apt-get update
      as_root apt-get install -y gh
    elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y gh
    elif command -v yum >/dev/null 2>&1; then as_root yum install -y gh
    elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm github-cli
    elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install gh
    elif command -v apk >/dev/null 2>&1; then as_root apk add github-cli
    else
      printf 'error: no supported package manager found; see https://github.com/cli/cli#installation\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'error: unsupported OS; see https://github.com/cli/cli#installation\n' >&2
    exit 1
    ;;
esac

command -v gh >/dev/null 2>&1 || {
  printf 'error: GitHub CLI installation completed but gh is not on PATH\n' >&2
  exit 1
}
