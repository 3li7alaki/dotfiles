#!/bin/bash
# Nudge toward codebase-memory-mcp for CODE discovery: block the first
# Grep/Glob/Read/Search of a session, allow every one after it.
#
# The sentinel key must be STABLE for the whole session. $PPID is not: the hook
# runs in a fresh shell per call, so its parent PID differs every time, the
# `[ -f $GATE ]` check never matches, and the gate blocks EVERY read forever
# while littering /tmp with one sentinel per call (126 of them, once). Use the
# harness session id, fall back to the stdin payload, never a per-process value.
STDIN=$(head -c 4096)
SID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SID" ]; then
    SID=$(printf '%s' "$STDIN" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
GATE="/tmp/cbm-code-discovery-gate-${SID:-default}"

# Reap sentinels from finished sessions.
find /tmp -maxdepth 1 -name 'cbm-code-discovery-gate-*' -mtime +1 -delete 2>/dev/null

[ -f "$GATE" ] && exit 0
touch "$GATE"

cat >&2 <<'MSG'
BLOCKED (once per session): for CODE discovery prefer codebase-memory-mcp — search_graph(name_pattern) to find functions/classes, trace_path() for call chains, get_code_snippet(qualified_name) to read source; index_repository first if the graph is cold.
Reading text/config/non-code files (yaml, md, json, toml) is a legitimate fallback: just retry and it will pass.
MSG
exit 2
