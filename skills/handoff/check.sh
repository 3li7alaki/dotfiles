#!/usr/bin/env bash
# Gate a handoff file before anyone acts on it. Section 5 of skills/handoff/SKILL.md is
# a checklist, and a checklist an agent grades itself against is the weakest part of the
# whole design: the failure is silent and it looks like success. A handoff that quietly
# omits Traps reads perfectly well and is precisely the one that costs you a day.
#
# So the checks that can be deterministic are deterministic. This does NOT judge whether
# the content is any good, only that it is structurally honest: every section present,
# a real next action, referenced paths that still resolve, and the mode locked down.
#
# Usage: handoff-check.sh <file>
# Exit 0 = safe to hand over. Exit 1 = do not reset your session on this file yet.

set -uo pipefail

f=${1:-}
[ -n "$f" ] || { printf 'usage: handoff-check.sh <file>\n' >&2; exit 2; }
[ -f "$f" ] || { printf 'FAIL missing file: %s\n' "$f" >&2; exit 1; }

fails=0; warns=0
bad()  { printf 'FAIL %s\n' "$*"; fails=$((fails+1)); }
warn() { printf 'WARN %s\n' "$*"; warns=$((warns+1)); }

# ── structure ────────────────────────────────────────────────────────────────
[ -s "$f" ] || bad "file is empty"

# Present-but-empty is the case that matters. A missing header is obvious; a header with
# nothing under it is what happens when the model loses track mid-write.
for s in Intent State Decisions Traps Verified Assumed "Subagent findings" "Next action"; do
  if ! grep -q "^## $s\$" "$f"; then
    bad "section missing: $s"
    continue
  fi
  body=$(awk -v want="## $s" '
    $0 == want { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$f" | tr -d '[:space:]')
  [ -n "$body" ] || bad "section empty: $s"
done

grep -q '^## ---- paste below this line ----$' "$f" \
  || bad "no paste block, so there is nothing for the next session to open with"

# The paste block is the part that actually gets used. An empty one means the handoff
# passed every other check and is still unusable.
paste=$(awk '/^## ---- paste below this line ----$/ { inside = 1; next } inside { print }' "$f" | tr -d '[:space:]')
[ -n "$paste" ] || bad "paste block is empty"

# ── provenance ───────────────────────────────────────────────────────────────
grep -qE '^Written [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" || bad "no 'Written <ISO timestamp>' line"

worktree=$(grep -m1 '^worktree:' "$f" | sed 's/^worktree:[[:space:]]*//')
if [ -z "$worktree" ]; then
  bad "State names no worktree, so nothing below it can be checked against reality"
elif [ ! -d "$worktree" ]; then
  bad "worktree does not exist: $worktree"
fi

# Staleness is expected, not a failure: these files are meant to be consumed quickly and
# to be verified on arrival. Say it out loud rather than pretending it is still current.
sha=$(grep -m1 -oE '@ [0-9a-f]{7,40}' "$f" | awk '{print $2}')
if [ -n "$sha" ] && [ -n "$worktree" ] && [ -d "$worktree" ]; then
  head=$(git -C "$worktree" rev-parse --short HEAD 2>/dev/null)
  case $head in "") ;; "$sha"*) ;; *)
    warn "written at $sha, worktree is now at $head, so State is stale by at least one commit" ;;
  esac
fi

# ── referenced paths ─────────────────────────────────────────────────────────
# Only the State bullet list, whose shape the template fixes. Guessing at paths in free
# prose would produce false alarms, and a gate that cries wolf gets ignored.
if [ -n "$worktree" ] && [ -d "$worktree" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case $p in *[![:alnum:]_./-]*) continue ;; esac   # prose, not a path
    case $p in */*|*.*) ;; *) continue ;; esac
    [ -e "$worktree/$p" ] || [ -e "$p" ] \
      || warn "referenced path no longer resolves: $p"
  done < <(awk '
    /^## State$/ { inside = 1; next }
    inside && /^## / { exit }
    inside && /^- / { sub(/^- /, ""); print $1 }
  ' "$f")
fi

# ── next action must be actionable ───────────────────────────────────────────
next=$(awk '/^## Next action$/ { inside = 1; next } inside && /^## / { exit } inside { print }' "$f")
case $(printf '%s' "$next" | tr '[:upper:]' '[:lower:]') in
  *"none known"*|*"not verified"*|*tbd*|*todo*)
    bad "Next action is a placeholder; it has to name one concrete thing" ;;
esac

# ── house rules + hygiene ────────────────────────────────────────────────────
n=$(grep -c $'—\|–' "$f")
[ "$n" -eq 0 ] || bad "$n em/en dash(es); the house rule forbids them"

mode=$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null)
[ "$mode" = "600" ] || warn "mode is $mode, expected 600 (run chmod 600)"

# Deterministic scan only if the tool is here. The real control is that the model authors
# this file rather than dumping a transcript into it, so nothing lands unless it chose to.
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --no-git --source "$f" --no-banner -q >/dev/null 2>&1 \
    || bad "gitleaks flagged a possible credential"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$fails" -gt 0 ]; then
  printf '\n%s: %d failure(s), %d warning(s). Fix before resetting the session.\n' "$(basename "$f")" "$fails" "$warns"
  exit 1
fi
printf '\nok: %s (%d warning(s))\n' "$(basename "$f")" "$warns"
exit 0
