#!/usr/bin/env bash
# cc-statusline — one-line Claude Code status bar, tuned to this setup.
#
# Reads session JSON on stdin (see `code.claude.com/docs/en/statusline`), prints
# ONE line. Segments, priority high→low (truncates right-first to fit $COLUMNS):
#   ctxbar% · 5h/7d · [model·1M] · cwd branch*⑂wt · effort⚡ · ●local · 🎙voice · 🖥remote · session
#
# Design notes:
#   - ctx bar bands on the HANDOFF threshold (~45%), not the 90% compact cliff:
#     this user never compacts, they ask for a handoff prompt around 40-50%.
#   - git + local-model health probed at most once / CACHE_SECS, keyed by
#     session_id (stable per session — $$ would defeat the cache, see docs).
#   - local model up/down is NOT in the CC JSON; probed via llama-server /health.
#   - wire with refreshInterval so the clock + local badge stay live while idle.
#
# ponytail: fixed 5-char bar + right-first truncation. If a segment needs its own
# width logic, add it then — not before.

HANDOFF_WARN=${CCSL_HANDOFF_WARN:-40}   # yellow at/above
HANDOFF_HARD=${CCSL_HANDOFF_HARD:-50}   # red + ⚑ at/above — "get a handoff prompt now"
CACHE_SECS=${CCSL_CACHE_SECS:-5}
MODELS_LINK="${CCSL_MODELS_LINK:-$HOME/.local/share/models/local.gguf}"
LOCAL_HEALTH="${CCSL_LOCAL_HEALTH:-http://127.0.0.1:8080/health}"
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
  [ "$(curl -s -m 0.2 -o /dev/null -w '%{http_code}' "$LOCAL_HEALTH" 2>/dev/null)" = "200" ] && UP=1
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

# 1. context bar — bands on handoff threshold (~45%), ⚑ at hard. THE number for this box.
if   [ "$PCT" -ge "$HANDOFF_HARD" ]; then BC=$R; FLAG=" ⚑"
elif [ "$PCT" -ge "$HANDOFF_WARN" ]; then BC=$Y; FLAG=""
else BC=$G; FLAG=""; fi
FILLED=$(( PCT * 5 / 100 )); [ "$FILLED" -gt 5 ] && FILLED=5
printf -v F "%${FILLED}s"; printf -v E "%$((5-FILLED))s"
BAR="${F// /▓}${E// /░}"
add "${B}${BC}${BAR} ${PCT}%${FLAG}${X}" "$BAR ${PCT}%${FLAG}"

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
