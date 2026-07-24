#!/usr/bin/env bash
# Weekly CLAUDE.md hygiene (wired via [cron.revise-claude-md] in config.toml).
# Runs /revise-claude-md headless against every ~/Projects repo that has a
# CLAUDE.md — pairs with the claude-md-management plugin's auto-capture skill:
# capture grows the files during sessions, this keeps them pruned without a
# human in the loop. Edits land uncommitted; review via git diff.
#
# Deliberately NOT run against the dotfiles hub CLAUDE.md — that one is
# hand-curated philosophy plus a generated routing block; auto-revision
# would mangle it.
set -u
export PATH="$HOME/.local/bin:$PATH"
command -v claude >/dev/null || { echo "claude not on PATH — skip"; exit 0; }

for f in "$HOME"/Projects/*/CLAUDE.md; do
  [ -f "$f" ] || continue
  d=$(dirname "$f")
  echo "[$(date '+%F %T')] revising $f"
  # NOT /revise-claude-md — that harvests the current session (empty under cron).
  # The claude-md-improver skill audits the file itself, which works headless.
  (cd "$d" && timeout 900 claude -p "Use the claude-md-improver skill: audit ./CLAUDE.md against its quality criteria and revise it in place — prune bloat, deduplicate, fix stale claims (verify them against the actual repo), keep it concise. Edit the file directly; no approval needed." \
      --permission-mode acceptEdits --max-turns 25) \
    || echo "  ⚠ failed/timed out for $d (continuing)"
done
echo "[$(date '+%F %T')] done"
