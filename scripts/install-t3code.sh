#!/usr/bin/env bash
# Install T3 Code: the desktop app on macOS, plus a real `t3` binary on every platform.
#
# The CLI used to be a wrapper around `npx -y t3@latest`, which resolved against the npm
# registry on every single invocation. That is tolerable when a human types `t3` once a
# day and wrong for the SlayZone automation, which runs `t3 project add` every time a task
# starts: a registry round trip in the hot path, and a hard failure with no network. A
# global install gives the same command with none of that; `t3 update` and setup keep it
# current instead of `@latest` doing it per call.
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v npm >/dev/null 2>&1 || die "T3 Code requires Node.js and npm"

case "$OS" in
  darwin)
    command -v brew >/dev/null 2>&1 || die "Homebrew is required on macOS: https://brew.sh"
    brew list --cask t3-code >/dev/null 2>&1 || brew install --cask t3-code
    ;;
  linux)
    # No cask on Linux; the npm CLI below can run the server headless with `t3 serve`.
    ;;
  *)
    die "unsupported OS: $OS (Windows installation is managed outside this Bash bootstrap)"
    ;;
esac

npm install -g t3 >/dev/null

# Retire the old npx shim. It lives in ~/.local/bin, which precedes the npm global bin on
# PATH, so leaving it would silently shadow the binary this script just installed.
if [ -L "$LOCAL_BIN/t3" ]; then
  rm -f "$LOCAL_BIN/t3"
  printf '  removed the old npx shim at %s/t3\n' "$LOCAL_BIN"
fi

command -v t3 >/dev/null 2>&1 || die "t3 installed but is not on PATH; check $(npm prefix -g)/bin"
printf '  t3 CLI -> %s\n' "$(command -v t3)"
