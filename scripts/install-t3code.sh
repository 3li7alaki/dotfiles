#!/usr/bin/env bash
# Install T3 Code on macOS and provide a cross-platform `t3` launcher.
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v npx >/dev/null 2>&1 || die "T3 Code requires Node.js and npx"
mkdir -p "$LOCAL_BIN"

case "$OS" in
  darwin)
    command -v brew >/dev/null 2>&1 || die "Homebrew is required on macOS: https://brew.sh"
    brew list --cask t3-code >/dev/null 2>&1 || brew install --cask t3-code
    ;;
  linux)
    # The official npx distribution is the most portable Linux surface and stays current.
    ;;
  *)
    die "unsupported OS: $OS (Windows installation is managed outside this Bash bootstrap)"
    ;;
esac

ln -sfn "$DOTFILES/scripts/t3" "$LOCAL_BIN/t3"
printf '  t3 launcher -> %s\n' "$LOCAL_BIN/t3"
