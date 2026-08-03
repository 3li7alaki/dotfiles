#!/usr/bin/env bash
# distill-memory.sh: promote repeated guidance out of transcripts into candidate memories.
# Wired via [cron.distill-memory] in config.toml.
#
# The problem: a memory file only exists if someone thinks to write it mid-session, so a
# rule stated four times across four sessions is still written down nowhere. This reads the
# transcripts that already sit in ~/.claude/projects, distills each session's typed prompts
# into normalized candidate rules, and promotes only the ones that recur across 2+ distinct
# sessions. One occurrence is noise.
#
# Four tiers, borrowed from TencentDB-Agent-Memory's pyramid, minus its service:
#   L0  raw transcripts, already on disk, untouched
#   L1  typed user prompts, extracted by jq (no model)
#   L2  candidate rules, one distill call per session (gpt-5.6-luna, chatgpt pool)
#   L3  candidates seen in 2+ sessions, written to a STAGING file for human review
#
# It never writes into a memory/ directory. A pass that writes its own behavioral rules and
# reads them back next session is grading its own homework: the accept step stays human.
#
# Usage:
#   distill-memory.sh              # drain up to $BATCH unseen sessions, then promote
#   distill-memory.sh --backfill   # no batch cap, walks all unseen sessions
#   distill-memory.sh --merge      # rebuild the slug alias map (one model call)
#   distill-memory.sh --promote    # re-run promotion over existing candidates, no model calls
#   distill-memory.sh --self-check # extractor assertions against an inline fixture

set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRUBBER="$SCRIPT_DIR/scrub-transcripts.py"
AGENTS_MD="${AGENTS_MD:-$(dirname "$SCRIPT_DIR")/AGENTS.md}"

PROJECTS="${CLAUDE_PROJECTS:-$HOME/.claude/projects}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/distill-memory"
SEEN="$STATE/seen.txt"
CANDIDATES="$STATE/candidates.jsonl"
SLUGMAP="$STATE/slug-map.json"
BATCH="${BATCH:-40}"          # sessions distilled per run; weekly cron drains the backlog
MIN_CHARS=1500                # below this a session has no rule worth extracting
MAX_CHARS=60000               # ponytail: hard truncation per session, raise if tails matter
MIN_SESSIONS=2                # recurrence threshold for promotion

mkdir -p "$STATE"
touch "$SEEN" "$CANDIDATES"

# ── L1: typed user prompts ───────────────────────────────────────────────────
# Keeps only what the human actually typed. Drops subagent sidechains, tool results
# (array content), slash-command wrappers, and one-word acks like "go" that carry no rule.
extract() {
  jq -r '
    select(.type == "user" and .isSidechain == false and (.message.content | type == "string"))
    | .message.content
    | select(test("<command-name>|<local-command-caveat>") | not)
    | select(length >= 15)
  ' -- "$1" 2>/dev/null | scrub
}

# Trust boundary: transcripts leave the box for the distill call, so anything shaped like a
# credential is redacted first. The patterns are NOT duplicated here. They live in
# scrub-transcripts.py, whose --filter mode adds the over-eager egress rules on top, and the
# second copy that used to sit here is precisely what shipped a live PEM body to the model:
# the whole-block fix landed in the Python file and never reached this sed.
# Line-based tools are the wrong shape for this anyway. jq -r has already turned the
# transcript's \n escapes into real newlines by the time we see the text, so a PEM arrives
# split across physical lines and sed can only ever match its header.
# ponytail: shape-matching only. A secret with no keyword and no recognizable prefix (a bare
# base64 blob, say) still gets through. Add a local-model secret pass if that ever bites.
scrub() {
  python3 "$SCRUBBER" --filter
}

DISTILL_PROMPT=$(cat <<'EOF'
Below are the prompts one developer typed to a coding agent during a single session.

Extract only DURABLE GUIDANCE: preferences, corrections, and standing rules about how the
agent should work. A correction ("no, do X instead"), a stated preference ("always use Y"),
or a constraint on process counts. One-off task instructions, questions, and anything true
only of the task at hand do NOT count. Most sessions yield zero or one. Returning nothing is
the correct answer for a session that is purely task work.

Output one JSON object per line, nothing else. No prose, no markdown fence. Fields:
  slug   kebab-case identifier for the RULE, not this phrasing of it. Two sessions stating
         the same rule differently must produce the same slug. Prefer short and general:
         "no-em-dashes", not "user-said-no-dashes-in-commit-messages".
  scope  "global" if the rule holds in any repository, "project" if it is only true of this
         codebase, its stack, or its conventions.
  type   "feedback" for guidance on how to work, "user" for who the developer is or what
         they prefer, "project" for a constraint or goal of this codebase.
  claim  one sentence, imperative, stating the rule.
  why    one sentence on why it holds. Empty string if the transcript does not say.
  apply  one sentence on what to do differently because of it.

Never use an em dash or an en dash in any field.
EOF
)

# ── L2: one distill call per session ─────────────────────────────────────────
distill() {
  local file="$1" proj="$2" sid text out
  sid=$(basename "$file" .jsonl)
  text=$(extract "$file")
  [ "${#text}" -ge "$MIN_CHARS" ] || { echo "$sid" >>"$SEEN"; return 0; }

  out=$(printf '%s\n\n--- SESSION PROMPTS ---\n%s\n' \
          "$DISTILL_PROMPT" "$(printf '%s' "$text" | head -c "$MAX_CHARS")" \
        | codex exec -s read-only --skip-git-repo-check \
            -c model=gpt-5.6-luna -c model_reasoning_effort="high" - 2>/dev/null)

  if [ -z "$out" ]; then
    echo "  ! distill failed for $sid (leaving unseen, will retry next run)" >&2
    return 1
  fi

  # codex prints a banner and reasoning around the answer; keep only well-formed rule lines.
  printf '%s\n' "$out" \
    | jq -c --arg sid "$sid" --arg proj "$proj" \
        'select(type == "object" and .slug and .claim) | . + {session: $sid, project: $proj}' \
        2>/dev/null >>"$CANDIDATES"

  echo "$sid" >>"$SEEN"
}

# ── L2.5: merge slugs that name the same rule ────────────────────────────────
# The first backfill settled this empirically: 578 rows produced 496 distinct slugs, and the
# duplicates were semantic, not textual. "no-ai-attribution" and "no-ai-commit-attribution"
# are one rule; "use-worktree" and "isolated-worktree" are one rule that shares a single word.
# String distance gets the first pair and botches the second, so this is a model call. One
# call over every slug plus its claim, roughly 10k tokens.
MERGE_PROMPT=$(cat <<'EOF'
Below is a list of rule identifiers and the rule each one states, one per line, as
slug<TAB>claim.

Several slugs name the SAME underlying rule in different words. Group them. Two slugs merge
only if following one is the same as following the other; a shared topic word is not enough.
"no-git-stash" and "no-rebase-force-push" are both about git and must NOT merge.

Output one JSON object per line, nothing else, only for groups of 2 or more:
  canonical  the clearest slug in the group, chosen from the input
  aliases    every other slug in the group

A slug that belongs to no group is omitted entirely. Never use an em dash or an en dash.
EOF
)

merge() {
  local pairs out
  pairs=$(jq -r '[.slug, .claim] | @tsv' "$CANDIDATES" | sort -u -t"$(printf '\t')" -k1,1)
  [ -n "$pairs" ] || { echo "  nothing to merge"; return 0; }

  out=$(printf '%s\n\n--- SLUGS ---\n%s\n' "$MERGE_PROMPT" "$pairs" \
        | codex exec -s read-only --skip-git-repo-check \
            -c model=gpt-5.6-luna -c model_reasoning_effort="high" - 2>/dev/null)

  printf '%s\n' "$out" \
    | jq -c 'select(type == "object" and .canonical and (.aliases | type == "array"))' 2>/dev/null \
    | jq -s 'map(.canonical as $c | .aliases[] | {(.): $c}) | add // {}' >"$SLUGMAP"

  echo "  merged $(jq -r 'length' "$SLUGMAP") alias(es) into canonical slugs"
}

# ── L3: promote what recurs, into a staging file per scope ───────────────────
promote() {
  local scope_dirs p src="$CANDIDATES"
  # Fold aliases onto their canonical slug before counting, so a rule stated three ways
  # across three sessions clears the threshold instead of sitting below it as three singles.
  if [ -s "$SLUGMAP" ]; then
    src="$STATE/candidates.folded.jsonl"
    jq -c --slurpfile mapf "$SLUGMAP" '.slug = ($mapf[0][.slug] // .slug)' "$CANDIDATES" >"$src"
  fi

  scope_dirs=$(jq -r 'select(.scope == "project") | .project' "$src" | sort -u)

  write_staging global "$(jq -c 'select(.scope != "project")' "$src")"
  for p in $scope_dirs; do
    write_staging "$p" "$(jq -c --arg p "$p" 'select(.scope == "project" and .project == $p)' "$src")"
  done
}

write_staging() {
  local scope="$1" rows="$2" out slug n kept=0 g=0
  [ -n "$rows" ] || return 0
  out="$STATE/candidates-$scope.md"
  [ "$scope" = global ] && g=1

  # A global rule is accepted as literal text in AGENTS.md, not as a memory file. Two reasons,
  # and the first is fatal on its own: a per-project memory directory keyed on $HOME loads in
  # no repository session, so the path this used to name was somewhere a rule went to die.
  # Second, AGENTS.md is the only one of these files Codex, opencode and Cursor read, and it
  # says itself that a rule which must hold has to be literal there rather than behind an
  # import. Project rules keep the memory-file form: that scope is Claude's and the harness
  # loads it. The block emitted below follows the destination, so nothing has to be restripped.
  {
    echo "# Memory candidates: $scope"
    echo
    echo "Seen in $MIN_SESSIONS or more distinct sessions."
    if [ "$g" = 1 ]; then
      echo "Accept one by adding its line as literal text under the right section of"
      echo "\`$AGENTS_MD\`. Drop any rule already stated there; the recurrence count only means"
      echo "the rule is real, not that it is missing."
    else
      echo "Accept one by writing it as a file in"
      echo "\`$PROJECTS/$scope/memory/\`, then adding its pointer line to MEMORY.md."
    fi
    echo
  } >"$out"

  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    n=$(printf '%s\n' "$rows" | jq -r --arg s "$slug" 'select(.slug == $s) | .session' | sort -u | wc -l | tr -d ' ')
    [ "$n" -ge "$MIN_SESSIONS" ] || continue
    kept=$((kept + 1))
    # One block per slug, from its first sighting; the later restatements add only count.
    printf '%s\n' "$rows" | jq -sr --arg s "$slug" --arg n "$n" --arg g "$g" '
      map(select(.slug == $s)) | .[0] |
      (if $g == "1" then [
        "## \(.slug)  (\($n) sessions)",
        "",
        "- \(.claim)",
        (if .why == "" then empty else "  Why: \(.why)" end),
        "  Apply: \(.apply)",
        ""
      ] else [
        "## \(.slug)  (\($n) sessions)",
        "",
        "```markdown",
        "---",
        "name: \(.slug)",
        "description: \(.claim)",
        "metadata:",
        "  type: \(.type)",
        "---",
        "",
        .claim,
        "",
        (if .why == "" then empty else "**Why:** \(.why)" end),
        "**How to apply:** \(.apply)",
        "```",
        ""
      ] end) | join("\n")' >>"$out"
  done < <(printf '%s\n' "$rows" | jq -r .slug | sort -u)

  echo "  $scope: $kept candidate(s) -> $out"
}

# ── self-check ───────────────────────────────────────────────────────────────
self_check() {
  local fix out
  fix=$(mktemp)
  cat >"$fix" <<'EOF'
{"type":"user","isSidechain":false,"message":{"content":"always run the tests before you claim a thing is done"}}
{"type":"user","isSidechain":true,"message":{"content":"subagent chatter that must never be extracted"}}
{"type":"user","isSidechain":false,"message":{"content":[{"type":"tool_result","content":"tool output"}]}}
{"type":"user","isSidechain":false,"message":{"content":"<command-name>/clear</command-name>"}}
{"type":"user","isSidechain":false,"message":{"content":"go"}}
{"type":"assistant","isSidechain":false,"message":{"content":"my own reply"}}
{"type":"user","isSidechain":false,"message":{"content":"the api_key = hunter2supersecret must not leave the box"}}
{"type":"user","isSidechain":false,"message":{"content":"deploy the commit 08dabd5345b37fffcbe335bd578b15a0 to staging please"}}
{"type":"user","isSidechain":false,"message":{"content":"here is the key -----BEGIN RSA PRIVATE KEY-----\nMIIEbodyzz9\nQQQsecondline\n-----END RSA PRIVATE KEY----- please keep it"}}
EOF
  out=$(extract "$fix")
  rm -f "$fix"

  [ "$(printf '%s\n' "$out" | grep -c .)" -eq 4 ] || { echo "FAIL: expected 4 kept lines, got: $out"; return 1; }
  printf '%s' "$out" | grep -q 'always run the tests'   || { echo "FAIL: dropped a real prompt"; return 1; }
  printf '%s' "$out" | grep -q 'subagent chatter'       && { echo "FAIL: kept a sidechain"; return 1; }
  printf '%s' "$out" | grep -q 'tool output'            && { echo "FAIL: kept a tool result"; return 1; }
  printf '%s' "$out" | grep -q 'command-name'           && { echo "FAIL: kept a slash command"; return 1; }
  printf '%s' "$out" | grep -q 'my own reply'           && { echo "FAIL: kept an assistant turn"; return 1; }
  printf '%s' "$out" | grep -q 'hunter2supersecret'     && { echo "FAIL: leaked a secret past scrub"; return 1; }
  printf '%s' "$out" | grep -q '08dabd5345b37fff'       && { echo "FAIL: leaked a bare hex blob past scrub"; return 1; }
  printf '%s' "$out" | grep -q 'MIIEbodyzz9'            && { echo "FAIL: leaked a PEM key body past scrub"; return 1; }
  printf '%s' "$out" | grep -q 'QQQsecondline'          && { echo "FAIL: leaked a PEM key body past scrub"; return 1; }
  printf '%s' "$out" | grep -q 'REDACTED'               || { echo "FAIL: scrub did not redact"; return 1; }

  echo "self-check ok"
}

# ── main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
  --self-check) self_check; exit $? ;;
  --extract)    extract "$2"; exit 0 ;;   # inspect L1 for one session, no model call
  --merge)      merge;      exit 0  ;;
  --promote)    promote;    exit 0  ;;
  --backfill)   BATCH=100000 ;;
esac

command -v jq      >/dev/null || { echo "jq not on PATH, skipping"; exit 0; }
command -v codex   >/dev/null || { echo "codex not on PATH, skipping"; exit 0; }
# Not "skipping": python3 IS the scrubber, so a missing one means the next distill call ships
# unredacted transcripts to the model. Refuse the run instead.
command -v python3 >/dev/null || { echo "python3 missing, refusing to distill unscrubbed"; exit 1; }
[ -r "$SCRUBBER" ]            || { echo "scrubber missing at $SCRUBBER, refusing to distill"; exit 1; }

self_check >/dev/null || { echo "extractor self-check failed, refusing to run"; exit 1; }

done_count=0
for f in "$PROJECTS"/*/*.jsonl; do
  [ -f "$f" ] || continue
  [ "$done_count" -lt "$BATCH" ] || break
  sid=$(basename "$f" .jsonl)
  grep -qxF "$sid" "$SEEN" && continue
  proj=$(basename "$(dirname "$f")")
  echo "[$(date '+%F %T')] distilling $proj/$sid"
  distill "$f" "$proj"
  done_count=$((done_count + 1))
done

remaining=$(( $(ls "$PROJECTS"/*/*.jsonl 2>/dev/null | wc -l) - $(sort -u "$SEEN" | grep -c .) ))
echo "[$(date '+%F %T')] distilled $done_count session(s), ~$remaining unseen remaining"
merge
promote
