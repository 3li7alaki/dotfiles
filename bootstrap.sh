#!/usr/bin/env bash
# Fresh-machine entry point:
#   curl -fsSL https://raw.githubusercontent.com/3li7alaki/dotfiles/main/bootstrap.sh | bash
#
# Ensures git, clones the repo if absent, runs setup.sh. Idempotent — safe to re-run.
set -eu

REPO="https://github.com/3li7alaki/dotfiles.git"
DEST="${DOTFILES_DIR:-$HOME/personal/dotfiles}"

err() { printf 'error: %s\n' "$*" >&2; exit 1; }

# git is the one prerequisite realistically missing on a minimal image. Detect the
# package manager and print exact remediation rather than a silent sudo the user can't run.
if ! command -v git >/dev/null 2>&1; then
  if   command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y git
  elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y git
  elif command -v pacman  >/dev/null 2>&1; then sudo pacman -S --noconfirm git
  elif command -v brew    >/dev/null 2>&1; then brew install git
  else err "git not found and no known package manager — install git, then re-run"; fi
fi
# macOS does not ship a dependable Python 3. Install it through the available package
# manager just like Git; setup needs 3.11+ for the standard-library TOML parser.
if ! command -v python3 >/dev/null 2>&1; then
  if   command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y python3
  elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y python3
  elif command -v pacman  >/dev/null 2>&1; then sudo pacman -S --noconfirm python
  elif command -v brew    >/dev/null 2>&1; then brew install python
  else err "Python 3.11+ required and no known package manager found — install it, then re-run"; fi
fi

python3 -c 'import tomllib' 2>/dev/null || err "Python 3.11+ required (tomllib is missing)"

if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only
else
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO" "$DEST"
fi

exec "$DEST/setup.sh"
