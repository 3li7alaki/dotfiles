#!/usr/bin/env bash
# repath-claude-projects.sh — remap Claude Code project dirs across a machine move.
#
# Claude Code stores per-project history + memory under ~/.claude/projects/<dir>, where
# <dir> is the CWD's absolute path with every '/' replaced by '-'. When repos move to a
# new path (e.g. OLD_ROOT/proj -> NEW_ROOT/proj) the encoded names stop matching, so old
# sessions/memories don't associate. This remaps them by prefix.
#
# Usage:
#   repath-claude-projects.sh [--src DIR] [--dest DIR] [--apply] FROM_PATH TO_PATH
#     FROM_PATH   old real path prefix, e.g. /old/home
#     TO_PATH     new real path prefix, e.g. /new/home/dev
#     --src DIR   where source project dirs live      (default: ~/.claude/projects)
#     --dest DIR  where remapped dirs are written     (default: ~/.claude/projects)
#     --apply     perform it (default: dry-run, prints the from->to plan only)
#
# Merges via rsync (never deletes source, never clobbers newer). Idempotent — safe to
# re-run. Only dirs matching FROM's encoding are touched; scratchpad/other dirs skipped.
set -euo pipefail

SRC="$HOME/.claude/projects"; DEST="$HOME/.claude/projects"; APPLY=0; args=()
while [ $# -gt 0 ]; do case "$1" in
  --src)  SRC="$2";  shift 2 ;;
  --dest) DEST="$2"; shift 2 ;;
  --apply) APPLY=1;  shift ;;
  -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) args+=("$1"); shift ;;
esac; done
[ "${#args[@]}" -eq 2 ] || { echo "usage: $0 [--src D] [--dest D] [--apply] FROM_PATH TO_PATH" >&2; exit 2; }

FROM="${args[0]}"; TO="${args[1]}"
enc() { printf '%s' "$1" | sed 's|/|-|g'; }   # /old/home -> -old-home
FE="$(enc "$FROM")"; TE="$(enc "$TO")"
[ -d "$SRC" ] || { echo "src not found: $SRC" >&2; exit 1; }

echo "remap  $FROM ($FE*)  ->  $TO ($TE*)"
echo "src=$SRC  dest=$DEST  mode=$([ $APPLY -eq 1 ] && echo APPLY || echo dry-run)"
echo
n=0
for path in "$SRC"/*/; do
  name="$(basename "$path")"
  case "$name" in "$FE"|"$FE"-*) ;; *) continue ;; esac      # only FROM-encoded dirs
  newname="$TE${name#"$FE"}"
  files=$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')
  printf '  %s\n      -> %s   (%s files)\n' "$name" "$newname" "$files"
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$DEST/$newname"
    rsync -a --ignore-existing "$path" "$DEST/$newname/"   # merge, keep any newer local
  fi
  n=$((n+1))
done
echo
echo "$([ $APPLY -eq 1 ] && echo remapped || echo would-remap) $n project dir(s)"
