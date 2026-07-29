#!/usr/bin/env bash
# Stop hook: nudge for a handoff when the session has grown enough to be worth
# checkpointing, and only at a turn boundary (Stop fires after a response, so it
# structurally cannot land mid-tool-call).
#
# WHY GROWTH AND NOT A WINDOW PERCENTAGE:
#   A percentage of the window is not a unit of anything. 150k of conversation is
#   15% of a 1M window and 75% of a 200k one, for identical accumulated history.
#   Codex CLI and OpenCode both trigger on absolute tokens for this reason; Claude
#   Code is the one that uses a percentage, and it is the one that fires too late.
#   Baseline (CLAUDE.md + hooks + MCP catalogs, ~52k on this box, ~65k median) is
#   measured per session rather than configured, so this self-calibrates to whatever
#   a given machine loads.
#
# WHY A HIGH-WATER MARK:
#   Current context is NOT cumulative history. One auto-compaction drops it from
#   280k to 90k, and a naive growth metric then reports a small number forever after
#   -- the session that most needs a checkpoint becomes the one that evades it. The
#   high-water mark only ever rises, so compaction cannot hide accumulated history.
#
# WHY IT RE-NUDGES:
#   The hook detects, the model decides. If it suggests a handoff and no file ever
#   appears, marking the band "done" would mean insurance you believe you have and
#   do not. So a band is only closed by an ARTIFACT ON DISK; an unanswered nudge
#   retries once RENUDGE_DELTA more tokens have accumulated.
#
# FAIL OPEN, ALWAYS. Missing jq, unreadable transcript, malformed JSON, anything:
# exit 0 silently. A hook that breaks your session when IT breaks gets deleted.

set -uo pipefail

# ── knobs ────────────────────────────────────────────────────────────────────
CHECKPOINT_GROWTH=${HANDOFF_CHECKPOINT_GROWTH:-150000}  # conversation added since baseline
HARD_GROWTH=${HANDOFF_HARD_GROWTH:-300000}              # second, louder band
CEILING=${HANDOFF_CEILING:-450000}                      # absolute total, backstop for a
                                                        # contaminated baseline (a first
                                                        # turn carrying a huge pasted spec)
RENUDGE_DELTA=${HANDOFF_RENUDGE_DELTA:-60000}           # retry an ignored nudge after this
STATE_DIR=${HANDOFF_STATE_DIR:-$HOME/.local/state/handoff}

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# Claude Code's own hook docs: "For Stop/SubagentStop hooks, check stop_hook_active
# in the input and return success while it's true." Without this, the nudge causes a
# response, which fires Stop, which nudges again.
[ "$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null)" = "true" ] && exit 0

transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
session=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
[ -n "$transcript" ] && [ -r "$transcript" ] || exit 0
[ -n "$session" ] || exit 0
[ -n "$cwd" ] || cwd=$PWD

# ── current main-thread context size ─────────────────────────────────────────
# Tail rather than slurp. These transcripts reach tens of MB and this runs after
# every single response; `jq -s` over the whole file would make each turn feel
# sticky and the hook would be gone within a week. 512KB is ~15 assistant records on
# a real 8MB transcript, and only the last one is needed. isSidechain filters subagent
# turns, whose small windows would otherwise read as a context collapse. If the tail
# happens to be all sidechain, this reads nothing and stays quiet until the next turn.
#
# `fromjson?` per line, NOT `jq -s`: a byte-tail always cuts the first line in half,
# and a transcript being appended to concurrently can leave the last one half-written.
# Slurping either into jq fails the whole read, so the hook would silently never fire
# on exactly the large sessions it exists for. Bad lines are skipped, not fatal.
current=$(tail -c 512000 "$transcript" 2>/dev/null \
  | jq -Rn '[ inputs
              | fromjson?
              | select(type == "object")
              | select(.type == "assistant" and (.isSidechain // false) != true)
              | .message.usage
              | select(. != null)
              | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
            ] | last // empty' 2>/dev/null)

case "$current" in ''|*[!0-9]*) exit 0 ;; esac
[ "$current" -gt 0 ] || exit 0

# ── per-session state ────────────────────────────────────────────────────────
sess_dir="$STATE_DIR/sessions"
mkdir -p "$sess_dir" 2>/dev/null || exit 0
chmod 700 "$STATE_DIR" "$sess_dir" 2>/dev/null
state="$sess_dir/$session.json"

if [ -r "$state" ]; then
  baseline=$(jq -r '.baseline // 0'     "$state" 2>/dev/null)
  high=$(jq -r '.high_water // 0'       "$state" 2>/dev/null)
  band=$(jq -r '.band // ""'            "$state" 2>/dev/null)
  nudged_at=$(jq -r '.nudged_at_hw // 0' "$state" 2>/dev/null)
else
  baseline=0; high=0; band=""; nudged_at=0
fi
case "$baseline$high$nudged_at" in *[!0-9]*) baseline=0; high=0; nudged_at=0 ;; esac

# First sighting sets the baseline. Take the MIN of what we have seen rather than
# literally the first turn: if the hook is enabled mid-session, or the opening turn
# carried a large pasted payload, the first number read is not the floor.
if [ "$baseline" -eq 0 ] || [ "$current" -lt "$baseline" ]; then baseline=$current; fi
if [ "$current" -gt "$high" ]; then high=$current; fi

growth=$(( high - baseline ))

# ── which band, if any ───────────────────────────────────────────────────────
# The ceiling is a separate reason, not a louder version of the same one. A session
# already in flight when this hook is first enabled, or resumed from disk, can never
# have its true baseline measured: the first number seen becomes the baseline, so
# growth reads 0 forever. The absolute ceiling is what catches those, and saying
# "0k of conversation" at 600k total would be nonsense.
want=""; reason=""
if [ "$high" -ge "$CEILING" ]; then
  want="hard";       reason="$(( high / 1000 ))k total context, past the $(( CEILING / 1000 ))k ceiling"
elif [ "$growth" -ge "$HARD_GROWTH" ]; then
  want="hard";       reason="$(( growth / 1000 ))k of conversation on top of a $(( baseline / 1000 ))k baseline, $(( high / 1000 ))k total"
elif [ "$growth" -ge "$CHECKPOINT_GROWTH" ]; then
  want="checkpoint"; reason="$(( growth / 1000 ))k of conversation on top of a $(( baseline / 1000 ))k baseline, $(( high / 1000 ))k total"
fi

# A band is closed by an artifact, never by having mentioned it. Look for a handoff
# written for this session since the nudge went out.
repo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
slug=$(basename "${repo:-$cwd}")
artifact=$(ls -1 "$STATE_DIR/$slug/$session"-*.md 2>/dev/null | tail -1)

save() {
  printf '{"baseline":%d,"high_water":%d,"band":"%s","nudged_at_hw":%d}\n' \
    "$baseline" "$high" "$1" "$2" > "$state" 2>/dev/null
  chmod 600 "$state" 2>/dev/null
}

[ -z "$want" ] && { save "$band" "$nudged_at"; exit 0; }

if [ -n "$artifact" ]; then
  # Handoff exists. Close this band; the next one can still speak up later.
  save "$want" "$high"
  exit 0
fi

# Already asked for this band and nothing was written. Stay quiet until enough new
# context has accumulated to be worth asking again.
if [ "$band" = "$want" ] && [ $(( high - nudged_at )) -lt "$RENUDGE_DELTA" ]; then
  save "$band" "$nudged_at"
  exit 0
fi

save "$want" "$high"

if [ "$want" = "hard" ]; then
  msg="Context checkpoint (hard): $reason."
else
  msg="Context checkpoint: $reason."
fi

jq -cn --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: ($m + "\n\nIf you are at a clean seam (a unit of work just finished, not three files into a refactor), run the handoff skill now so this session is recoverable, then tell the user they can /clear. If you are mid-task, say nothing about this and carry on; you will be asked again later. Also worth a handoff regardless of the number if you notice yourself re-reading files you already read or re-deriving decisions already made.")
  }
}' 2>/dev/null

exit 0
