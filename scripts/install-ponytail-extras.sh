#!/usr/bin/env bash
# Ponytail beyond Claude Code.
#
# Claude Code gets ponytail as a plugin (config.toml drives that). The other
# harnesses on this box need their own wiring:
#
#   opencode : the plugin is published to npm as @dietrichgebert/ponytail and is
#              declared in configs/opencode.json, which setup renders into
#              ~/.config/opencode/opencode.json. opencode fetches it on next
#              launch, so there is nothing to install here. Verified only.
#   codex    : the repo doubles as a Codex marketplace via
#              .agents/plugins/marketplace.json, so `codex plugin add` works.
#   T3 Code  : drives Claude Code or Codex underneath and inherits whatever they
#              have. No separate wiring exists or is needed.
#
# Idempotent, safe to re-run, never fatal: a harness that is absent is skipped.
set -uo pipefail

MARKETPLACE="https://github.com/DietrichGebert/ponytail.git"
OPENCODE_JSON="$HOME/.config/opencode/opencode.json"

# opencode: assert the rendered config carries the npm plugin entry.
if command -v opencode >/dev/null 2>&1; then
  if grep -q '@dietrichgebert/ponytail' "$OPENCODE_JSON" 2>/dev/null; then
    printf 'ponytail: opencode plugin declared in %s\n' "$OPENCODE_JSON"
  else
    printf 'ponytail: warning, %s has no @dietrichgebert/ponytail entry (check configs/opencode.json)\n' "$OPENCODE_JSON"
  fi
else
  printf 'ponytail: opencode not installed, skipped\n'
fi

# codex: add the marketplace, then install the plugin if it is not already in.
if command -v codex >/dev/null 2>&1; then
  codex plugin marketplace add "$MARKETPLACE" >/dev/null 2>&1 || true
  # Capture before matching: `grep -q` closes the pipe on its first hit, and under
  # `pipefail` the resulting SIGPIPE on `codex plugin list` fails the whole pipeline.
  # The status column reads "installed" or "not installed", so anchor on the
  # whitespace run after the selector: a loose match treats "not installed" as a hit.
  plugins=$(codex plugin list 2>/dev/null || true)
  if printf '%s\n' "$plugins" | grep -qE '^ponytail@ponytail[[:space:]]+installed'; then
    printf 'ponytail: codex plugin already installed\n'
  elif codex plugin add ponytail@ponytail >/dev/null 2>&1; then
    printf 'ponytail: codex plugin installed\n'
  else
    printf 'ponytail: warning, codex plugin install failed (retry: codex plugin add ponytail@ponytail)\n'
  fi
else
  printf 'ponytail: codex not installed, skipped\n'
fi
