#!/usr/bin/env bash
# Install SlayZone and expose its bundled `slay` CLI without requiring a system-wide link.
set -euo pipefail

XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
LOCAL_BIN="$HOME/.local/bin"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

say() { printf '  %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v node >/dev/null 2>&1 || die "Slay CLI requires Node.js (install Node 22+ first)"
NODE_MAJOR=$(node -p 'Number(process.versions.node.split(".")[0])')
[ "$NODE_MAJOR" -ge 22 ] || die "Slay CLI requires Node 22+ (found $(node --version))"
mkdir -p "$LOCAL_BIN"

install_cli() {
  local src="$1" dest="$XDG_DATA/slayzone/cli"
  [ -x "$src" ] || die "bundled Slay CLI not found: $src"
  mkdir -p "$dest"
  cp "$src" "$dest/slay"
  cp "$(dirname "$src")/slay.js" "$dest/slay.js"
  chmod +x "$dest/slay"
  ln -sfn "$dest/slay" "$LOCAL_BIN/slay"
  say "slay CLI -> $LOCAL_BIN/slay"
}

case "$OS" in
  darwin)
    command -v brew >/dev/null 2>&1 || die "Homebrew is required on macOS: https://brew.sh"
    brew list --cask slayzone >/dev/null 2>&1 || brew install --cask slayzone
    app="/Applications/SlayZone.app"
    [ -d "$app" ] || app="$HOME/Applications/SlayZone.app"
    [ -d "$app" ] || die "SlayZone.app was not found after Homebrew installation"
    install_cli "$app/Contents/Resources/bin/slay"
    ;;
  linux)
    arch=$(uname -m)
    [ "$arch" = "x86_64" ] || die "automatic Linux install supports x86_64; use the official Nix package on $arch"
    app_dir="$XDG_DATA/slayzone"
    app="$app_dir/SlayZone.AppImage"
    mkdir -p "$app_dir"
    curl -fL "https://github.com/debuglebowski/slayzone/releases/latest/download/SlayZone-x86_64.AppImage" -o "$app"
    chmod +x "$app"
    ln -sfn "$app" "$LOCAL_BIN/slayzone"

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/slayzone.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    (cd "$tmp" && "$app" --appimage-extract >/dev/null)
    cli_src=$(find "$tmp/squashfs-root" -type f -path '*/resources/bin/slay' -print -quit)
    [ -n "$cli_src" ] || die "could not locate the bundled CLI in the AppImage"
    install_cli "$cli_src"
    say "SlayZone AppImage -> $LOCAL_BIN/slayzone"
    ;;
  *)
    die "unsupported OS: $OS (Windows installation is managed outside this Bash bootstrap)"
    ;;
esac

"$LOCAL_BIN/slay" --version
