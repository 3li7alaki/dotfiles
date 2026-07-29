#!/usr/bin/env bash
# cc-statusline — one-line Claude Code status bar, tuned to this setup.
#
# Reads session JSON on stdin (see `code.claude.com/docs/en/statusline`), prints
# ONE line. Segments, priority high→low (truncates right-first to fit $COLUMNS):
#   ctxbar% · 5h/7d · [model·1M] · cwd branch*⑂wt · effort⚡ · ●local · 🎙voice · 🖥remote · session
#
# Design notes:
#   - ctx bar is ABSOLUTE TOKENS against the handoff ceiling, not a percentage of
#     the window, and it flags whichever of the two constraints bites first. It
#     agrees with hooks/handoff-checkpoint.sh by construction.
#   - git + local-model health probed at most once / CACHE_SECS, keyed by
#     session_id (stable per session — $$ would defeat the cache, see docs).
#   - local model up/down is NOT in the CC JSON; probed via llama-server /health.
#   - wire with refreshInterval so the clock + local badge stay live while idle.
#
# ponytail: fixed 5-char bar + right-first truncation. If a segment needs its own
# width logic, add it then — not before.

# The bar measures context against the HANDOFF CEILING, not against the window. A
# percentage of the window is not a unit of anything: 215k of context is 21% of a 1M
# window and 107% of a 200k one, for identical accumulated history. Banding on the
# window meant this bar went yellow at 400k on the 1M box, long after
# hooks/handoff-checkpoint.sh had already asked for a handoff. Keep CEILING in step
# with HANDOFF_CEILING in that hook: 50% and 80% of it land on the hook's own
# checkpoint (~215k) and hard (~365k) totals, so the bar and the nudge agree.
HANDOFF_CEILING=${CCSL_HANDOFF_CEILING:-450000}   # tokens; mirrors the hook's ceiling
HANDOFF_WARN=${CCSL_HANDOFF_WARN:-50}   # yellow at/above, percent OF THE CEILING
HANDOFF_HARD=${CCSL_HANDOFF_HARD:-80}   # red + ⚑ at/above — "get a handoff prompt now"
CACHE_SECS=${CCSL_CACHE_SECS:-5}
MODELS_LINK="${CCSL_MODELS_LINK:-$HOME/.local/share/models/local.gguf}"
LOCAL_HEALTH="${CCSL_LOCAL_HEALTH:-http://127.0.0.1:18080/health}"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

# Bright ANSI — the 90m-dim look was unreadable; reserve dim only for separators.
G='\033[92m'; Y='\033[93m'; R='\033[91m'; C='\033[96m'; W='\033[97m'
D='\033[90m'; B='\033[1m'; X='\033[0m'
band() { # band <pct> — usage color: green calm / yellow watch / red hot
  [ "${1%.*}" -ge 80 ] 2>/dev/null && { printf '%s' "$R"; return; }
  [ "${1%.*}" -ge 50 ] 2>/dev/null && { printf '%s' "$Y"; return; }
  printf '%s' "$G"
}

input=$(cat)

# One jq call — spawning jq per field is the slow path the docs warn about.
# Newline-delimited (not @tsv): tab is IFS-whitespace, so `read` would collapse
# empty fields and shift every column. One value per line preserves empties.
i=0
while IFS= read -r line; do F[$i]="$line"; i=$((i+1)); done < <(printf '%s' "$input" | jq -r '
  .model.display_name // "?",
  (.context_window.context_window_size // 200000),
  (.context_window.used_percentage // 0),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.effort.level // ""),
  (.fast_mode // false),
  (.session_name // ""),
  (.workspace.git_worktree // ""),
  (.session_id // "x"),
  (.workspace.current_dir // .cwd // "")')
MODEL=${F[0]} CTXSIZE=${F[1]} PCT=${F[2]} FIVE=${F[3]} SEVEN=${F[4]} EFFORT=${F[5]}
FAST=${F[6]} SESS=${F[7]} WT=${F[8]} SID=${F[9]} CWD=${F[10]}

PCT=${PCT%.*}; [ -z "$PCT" ] && PCT=0
SID=${SID//\//_}   # session_id is trusted, but it lands in a /tmp path — belt + braces

# Absolute tokens in context, reconstructed from the two fields Claude Code gives us.
# TOK is the number the handoff hook talks in, so the bar and the nudge agree; BPCT is
# only how full the bar draws. BPCT can exceed 100 past the ceiling, which is the point.
case $CTXSIZE in ''|*[!0-9]*) CTXSIZE=200000 ;; esac
TOK=$(( CTXSIZE * PCT / 100 ))
BPCT=$(( TOK * 100 / HANDOFF_CEILING ))
if [ "$TOK" -ge 1000 ]; then TOKL="$(( TOK / 1000 ))k"; else TOKL="${TOK}"; fi

# Two independent constraints, and the bar shows whichever bites first. Handoff
# pressure is what binds on a 1M window; the window wall itself is what binds on a
# 200k one, where 190k is comfortably under the ceiling and still one turn from a
# forced compaction. Banding on the ceiling alone would have shown that green.
EPCT=$BPCT; [ "$PCT" -gt "$EPCT" ] && EPCT=$PCT

# ── cached probes (git branch/dirty + local health) ─────────────────────────
CACHE="${TMPDIR:-/tmp}/ccsl-$SID"
stale() {
  [ -f "$CACHE" ] || return 0
  local m; m=$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  [ $(( $(date +%s) - m )) -ge "$CACHE_SECS" ]
}
if stale; then
  BR=""; DIRTY=""
  if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BR=$(git -C "$CWD" branch --show-current 2>/dev/null)
    [ -n "$(git -C "$CWD" status --porcelain 2>/dev/null | head -1)" ] && DIRTY="*"
  fi
  UP=0
  # Match the payload, not the status code: another service on the same port answers 200 too.
  curl -s -m 0.2 "$LOCAL_HEALTH" 2>/dev/null | grep -q '"status":"ok"' && UP=1
  printf '%s\n%s\n%s\n' "$BR" "$DIRTY" "$UP" > "$CACHE"   # line-per-field: tab would collapse empties
fi
{ IFS= read -r BR; IFS= read -r DIRTY; IFS= read -r UP; } < "$CACHE" 2>/dev/null

# ── segment builder — priority order; wraps to more rows when narrow (nothing dropped) ──
COLS=${COLUMNS:-120}; BUDGET=$(( COLS - 6 ))   # reserve right edge for CC notifications
LINES=(); OUT=""; PLAIN=""
flush() { [ -n "$OUT" ] && LINES+=("$OUT"); OUT=""; PLAIN=""; }
add() { # add <colored> <plain>
  local np; [ -z "$PLAIN" ] && np="$2" || np="$PLAIN · $2"
  if [ -n "$PLAIN" ] && [ ${#np} -gt "$BUDGET" ]; then flush; np="$2"; fi
  [ -z "$OUT" ] && OUT="$1" || OUT="$OUT ${D}·${X} $1"
  PLAIN="$np"
}

# 1. context bar — fill and bands are against the handoff ceiling, and the label is
# absolute tokens rather than a percentage, because tokens are what the handoff hook
# reports and what the thresholds are actually set in. THE number for this box.
if   [ "$EPCT" -ge "$HANDOFF_HARD" ]; then BC=$R; FLAG=" ⚑"
elif [ "$EPCT" -ge "$HANDOFF_WARN" ]; then BC=$Y; FLAG=""
else BC=$G; FLAG=""; fi
FILLED=$(( EPCT * 5 / 100 )); [ "$FILLED" -gt 5 ] && FILLED=5; [ "$FILLED" -lt 0 ] && FILLED=0
printf -v F "%${FILLED}s"; printf -v E "%$((5-FILLED))s"
BAR="${F// /▓}${E// /░}"
add "${B}${BC}${BAR} ${TOKL}${FLAG}${X}" "$BAR ${TOKL}${FLAG}"

# 2. rate limits — each window colored by its own pressure (Max subscriber; absent otherwise)
RL=""; RLP=""
[ -n "$FIVE" ] && { p=$(printf '%.0f' "$FIVE"); RL="${W}5h $(band "$p")${B}${p}%${X}"; RLP="5h ${p}%"; }
[ -n "$SEVEN" ] && { p=$(printf '%.0f' "$SEVEN"); RL="${RL:+$RL }${W}7d $(band "$p")${B}${p}%${X}"; RLP="${RLP:+$RLP }7d ${p}%"; }
[ -n "$RL" ] && add "$RL" "$RLP"

# 3. model (+ 1M tag on extended context)
TAG=""; [ "$CTXSIZE" -gt 200000 ] 2>/dev/null && TAG="·1M"
add "${B}${C}[${MODEL}${TAG}]${X}" "[${MODEL}${TAG}]"

# 4. cwd + branch/dirty + worktree
DIR="${CWD/#$HOME/\~}"; DIR="${DIR##*/}"; [ -z "$DIR" ] && DIR="~"
GITSEG=""; GITPLAIN="$DIR"
[ -n "$BR" ] && { GITSEG=" ${Y}${BR}${R}${DIRTY}${X}"; GITPLAIN="$DIR $BR$DIRTY"; }
[ -n "$WT" ] && { GITSEG="${GITSEG} ${C}⑂${WT}${X}"; GITPLAIN="$GITPLAIN ⑂$WT"; }
add "${W}${DIR}${X}${GITSEG}" "$GITPLAIN"

# 5. effort + fast
if [ -n "$EFFORT" ] || [ "$FAST" = "true" ]; then
  ES="$EFFORT"; [ "$FAST" = "true" ] && ES="${ES}⚡"
  add "${C}${ES}${X}" "$ES"
fi

# 6. local model ●up (green) / ○down (dim)  — name from the symlink; skip if unknown
if [ -L "$MODELS_LINK" ] || [ -f "$MODELS_LINK" ]; then
  TGT=$(readlink "$MODELS_LINK" 2>/dev/null || echo "$MODELS_LINK")
  N=$(basename "$TGT"); N="${N%.gguf}"; N=$(printf '%s' "$N" | tr 'A-Z' 'a-z')
  IFS=- read -r a b _ <<<"$N"; SHORT="${a}${b:+-$b}"
  if [ "$UP" = "1" ]; then add "${G}●${W}${SHORT}${X}" "●${SHORT}"
  else add "${D}○${SHORT}${X}" "○${SHORT}"; fi
fi

# 7. voice 🎙 + remote 🖥 — show only when active (settings .voice.enabled / bridge env var)
[ "$(jq -r '.voice.enabled // false' "$SETTINGS" 2>/dev/null)" = "true" ] && add "${G}🎙${X}" "voice"
[ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID}${CLAUDE_CODE_REMOTE_SESSION_ID}" ] && add "${G}🖥${X}" "remote"

# 8. session name (lowest priority — identity label, wraps to last row when narrow)
[ -n "$SESS" ] && add "${D}${SESS}${X}" "$SESS"

flush
for l in "${LINES[@]}"; do printf '%b\n' "$l"; done
