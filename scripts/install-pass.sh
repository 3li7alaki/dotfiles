#!/usr/bin/env bash
# Install pass + GnuPG and expose the dotfiles-owned safe helper commands.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_BIN="$HOME/.local/bin"

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else printf 'error: installing pass requires root or sudo\n' >&2; exit 1
  fi
}

if ! command -v pass >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin)
      command -v brew >/dev/null 2>&1 || {
        printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
        exit 1
      }
      brew install pass gnupg
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then as_root apt-get install -y pass gnupg2
      elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y pass gnupg2
      elif command -v yum >/dev/null 2>&1; then as_root yum install -y pass gnupg2
      elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm pass gnupg
      elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install password-store gpg2
      elif command -v apk >/dev/null 2>&1; then as_root apk add pass gnupg
      else
        printf 'error: no supported package manager found; see https://www.passwordstore.org/\n' >&2
        exit 1
      fi
      ;;
    *)
      printf 'error: unsupported OS; see https://www.passwordstore.org/\n' >&2
      exit 1
      ;;
  esac
fi

command -v pass >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1 || {
  printf 'error: pass/GnuPG installation completed but required commands are missing\n' >&2
  exit 1
}

mkdir -p "$LOCAL_BIN"
ln -sfn "$DOTFILES/scripts/pass-env" "$LOCAL_BIN/pass-env"
ln -sfn "$DOTFILES/scripts/pass-fzf" "$LOCAL_BIN/pass-fzf"
printf '  pass helpers -> %s\n' "$LOCAL_BIN"
