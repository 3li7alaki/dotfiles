#!/usr/bin/env bash
# Caveman beyond Claude Code.
#
# Claude Code gets caveman as a plugin (config.toml drives that). The other
# harnesses on this box need their own wiring, and caveman ships a unified
# installer whose `--only <id>` rows do exactly that:
#
#   opencode : native plugin, commands, cavecrew agents, skills, plus an
#              always-on ruleset block in ~/.config/opencode/AGENTS.md. The
#              installer also patches its plugin entry into opencode.json.
#              Setup rewrites that file from configs/opencode.json during the
#              tools phase, which runs BEFORE the skills phase this script is
#              called from, so every setup run restores the entry.
#   codex    : the skills rows write to ./.agents/skills, relative to the working
#              directory, so this runs from $HOME to land them in ~/.agents/skills,
#              the same global path setup links mint and slay into. Skills alone
#              are per-session (/caveman), so the always-on rule is fenced into
#              ~/.codex/AGENTS.md separately below.
#   T3 Code  : drives Claude Code or Codex underneath and inherits from them.
#
# The installer needs a repo checkout, so it is invoked through the `github:`
# npx specifier rather than the published stub, which cannot do the opencode row.
#
# Idempotent, safe to re-run, never fatal: a harness that is absent is skipped.
set -uo pipefail

CAVEMAN_PKG="github:JuliusBrussee/caveman"
RULE_URL="https://raw.githubusercontent.com/JuliusBrussee/caveman/main/src/rules/caveman-activate.md"
CODEX_AGENTS="$HOME/.codex/AGENTS.md"

install_for() {
  local id="$1"
  # Run from $HOME: the codex row resolves its skills directory against the cwd.
  if (cd "$HOME" && npx -y "$CAVEMAN_PKG" -- --only "$id" --non-interactive) >/dev/null 2>&1; then
    printf 'caveman: %s wired\n' "$id"
  else
    printf 'caveman: warning, %s install failed (retry: npx -y %s -- --only %s)\n' \
      "$id" "$CAVEMAN_PKG" "$id"
  fi
}

# Always-on rule for Codex, whose plugin surface has no caveman adapter. Fenced so
# re-runs replace only this block and the dotfiles integrations block stays intact.
wire_codex_rule() {
  local rule begin='<!-- >>> dotfiles:caveman-activate >>> -->'
  local end='<!-- <<< dotfiles:caveman-activate <<< -->'
  rule=$(curl -fsSL "$RULE_URL" 2>/dev/null) || {
    printf 'caveman: warning, could not fetch the activation rule, codex left skills-only\n'
    return
  }
  BEGIN="$begin" END="$end" RULE="$rule" TARGET="$CODEX_AGENTS" python3 - <<'PY'
import os, re
from pathlib import Path

path = Path(os.environ["TARGET"])
begin, end = os.environ["BEGIN"], os.environ["END"]
block = f"{begin}\n{os.environ['RULE'].strip()}\n{end}"
text = path.read_text() if path.exists() else ""
pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
text = pattern.sub(block, text) if pattern.search(text) else \
    (text.rstrip("\n") + "\n\n" + block + "\n" if text.strip() else block + "\n")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text)
PY
  printf 'caveman: codex always-on rule -> %s\n' "$CODEX_AGENTS"
}

for harness in opencode codex; do
  if command -v "$harness" >/dev/null 2>&1; then
    install_for "$harness"
    [ "$harness" = codex ] && wire_codex_rule
  else
    printf 'caveman: %s not installed, skipped\n' "$harness"
  fi
done
