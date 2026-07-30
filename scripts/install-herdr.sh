#!/usr/bin/env bash
# Install herdr, preferring Homebrew when it is present and falling back to the
# vendor installer, which is the only supported path on a bare VPS.
set -euo pipefail

command -v herdr >/dev/null 2>&1 && exit 0

case "$(uname -s)" in
  Darwin)
    command -v brew >/dev/null 2>&1 || {
      printf 'error: Homebrew is required on macOS: https://brew.sh\n' >&2
      exit 1
    }
    brew install herdr
    ;;
  Linux)
    if command -v brew >/dev/null 2>&1; then
      brew install herdr
    else
      # Ships prebuilt linux-x86_64 and linux-aarch64 binaries into ~/.local/bin.
      curl -fsSL https://herdr.dev/install.sh | sh
    fi
    ;;
  *)
    printf 'error: unsupported OS; see https://herdr.dev/docs/quick-start/\n' >&2
    exit 1
    ;;
esac

command -v herdr >/dev/null 2>&1 || {
  printf 'error: herdr installed but is not on PATH; check ~/.local/bin\n' >&2
  exit 1
}
