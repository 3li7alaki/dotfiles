#!/usr/bin/env bash
# dotfiles setup — reads config.toml and installs/enables/disables each entry by type.
# Idempotent: run it any time. `--dry-run` prints what it would do and changes nothing.
# `--verify` runs only the final checks (exits nonzero if anything enabled is broken).
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
CONFIG="$DOTFILES/config.toml"
XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
# Entries may pin themselves to one OS (`os = "darwin"`). On the wrong box they're inert —
# skipped by setup and ignored by verify — never a failure. Keeps one config across machines.
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
DRY=false
DRY_LABEL=""
VERIFY_ONLY=false
UPDATE=false
case "${1:-}" in
  --dry-run) DRY=true; DRY_LABEL=" (dry-run)" ;;
  --verify)  VERIFY_ONLY=true ;;
  --update)  UPDATE=true; DRY_LABEL=" (update)" ;;   # re-run installers + brew upgrade to pull latest
esac

say()  { printf '  %s\n' "$*"; }
head() { printf '\n\033[1m%s\033[0m\n' "$*"; }
run()  { if $DRY; then printf '  would: %s\n' "$*"; else eval "$*"; fi; }
# GNU coreutils calls this `timeout`; Homebrew exposes it as `gtimeout`. If neither
# exists, preserve portability and run normally—the timeout is only a hang guard.
timeout_cmd() {
  local seconds="$1"; shift
  if command -v timeout >/dev/null 2>&1; then command timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then command gtimeout "$seconds" "$@"
  else "$@"
  fi
}
# resolve — expand config path tokens to real paths (portable — no hardcoded absolutes).
#   DOTFILES -> repo root | HOME -> $HOME | XDG_DATA/XDG_STATE -> XDG dirs
#   COMMAND:tool -> `command -v tool` (falls back to the bare name if not on PATH yet)
resolve() {
  local v="$1"
  v="${v/#DOTFILES/$DOTFILES}"; v="${v/#HOME/$HOME}"
  v="${v/#XDG_DATA/$XDG_DATA}"; v="${v/#XDG_STATE/$XDG_STATE}"
  case "$v" in COMMAND:*) v="$(command -v "${v#COMMAND:}" || echo "${v#COMMAND:}")" ;; esac
  printf '%s' "$v"
}

# shell_rc <shell> — the conventional interactive startup file for a supported shell.
shell_rc() {
  case "$1" in
    bash) printf '%s' "$HOME/.bashrc" ;;
    zsh)  printf '%s' "$HOME/.zshrc" ;;
    fish) printf '%s' "$XDG_CONFIG/fish/config.fish" ;;
    *)    return 1 ;;
  esac
}

# shell_init_set <tool-id> <command> <shell> <enabled>
# Owns only a marker-delimited block, leaving the rest of the user's rc file untouched.
shell_init_set() {
  local id="$1" command="$2" shell="$3" enabled="$4" args="${5:-}" verb="${6:-init}" rc
  rc=$(shell_rc "$shell") || return 1
  RC="$rc" ID="$id" COMMAND="$command" SHELL_NAME="$shell" ENABLED="$enabled" ARGS="$args" VERB="$verb" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["RC"])
tool = os.environ["ID"]
command = os.environ["COMMAND"]
shell = os.environ["SHELL_NAME"]
enabled = os.environ["ENABLED"] == "true"
args = os.environ.get("ARGS", "").strip()
verb = (os.environ.get("VERB", "init").strip() or "init")
start = f"# >>> dotfiles:{tool} >>>"
end = f"# <<< dotfiles:{tool} <<<"

text = path.read_text() if path.exists() else ""
while start in text:
    before, rest = text.split(start, 1)
    if end not in rest:
        text = before
        break
    _, after = rest.split(end, 1)
    text = before.rstrip("\n") + after

if enabled:
    if shell == "fish":
        init = f"{command} {verb} fish {args}".rstrip()
        body = f"if type -q {command}\n    {init} | source\nend"
    else:
        init = f"{command} {verb} {shell} {args}".rstrip()
        body = f'if command -v {command} >/dev/null 2>&1; then\n  eval "$({init})"\nfi'
    block = f"{start}\n{body}\n{end}"
    text = text.rstrip("\n")
    text = f"{text}\n\n{block}\n" if text else f"{block}\n"
elif text:
    text = text.rstrip("\n") + "\n"

if path.exists() or enabled:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
PY
}

# markdown_block_set <path> <id> <content-file> <enabled>
# Reconciles one marker-owned Markdown region while preserving every other instruction.
markdown_block_set() {
  local path="$1" id="$2" content="$3" enabled="$4"
  PATHNAME="$path" BLOCK_ID="$id" CONTENT="$content" ENABLED="$enabled" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["PATHNAME"])
start = f"<!-- >>> dotfiles:{os.environ['BLOCK_ID']} >>> -->"
end = f"<!-- <<< dotfiles:{os.environ['BLOCK_ID']} <<< -->"
text = path.read_text() if path.exists() else ""
while start in text:
    before, rest = text.split(start, 1)
    if end not in rest:
        text = before
        break
    _, after = rest.split(end, 1)
    text = before.rstrip("\n") + after

if os.environ["ENABLED"] == "true":
    body = Path(os.environ["CONTENT"]).read_text().strip()
    block = f"{start}\n{body}\n{end}"
    text = text.rstrip("\n")
    text = f"{text}\n\n{block}\n" if text else f"{block}\n"
elif text:
    text = text.rstrip("\n") + "\n"

if path.exists() or os.environ["ENABLED"] == "true":
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
PY
}

command -v python3 >/dev/null || { echo "need python3 to read config.toml" >&2; exit 1; }

# Ensure ~/.local/bin on PATH (login profile may not have; cron/non-login need it).
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# cfg <dotted.path> — read a scalar/array from config.toml, with config.local.toml
# (gitignored, per-box) deep-merged on top. Arrays come back as JSON.
cfg() { CONFIG="$CONFIG" python3 - "$1" <<'PY'
import os, sys, json
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
def merged():
    with open(os.environ["CONFIG"],"rb") as f: data = tomllib.load(f)
    local = os.environ["CONFIG"].replace("config.toml", "config.local.toml")
    if os.path.exists(local):
        def deep(dst, src):
            for k, v in src.items():
                if isinstance(v, dict) and isinstance(dst.get(k), dict): deep(dst[k], v)
                else: dst[k] = v
        with open(local,"rb") as f: deep(data, tomllib.load(f))
    return data
path = sys.argv[1].split(".")
cur = merged()
for k in path:
    if isinstance(cur, dict) and k in cur: cur = cur[k]
    else: sys.exit(0)
print(json.dumps(cur) if not isinstance(cur,(str,)) else cur)
PY
}

# section_keys <table> — list the sub-keys of a [table] (e.g. tools -> rtk mint codex),
# including any per-box sub-keys added by config.local.toml.
section_keys() { CONFIG="$CONFIG" python3 - "$1" <<'PY'
import os, sys, tomllib
with open(os.environ["CONFIG"],"rb") as f: data = tomllib.load(f)
local = os.environ["CONFIG"].replace("config.toml", "config.local.toml")
if os.path.exists(local):
    with open(local,"rb") as f:
        for k, v in tomllib.load(f).get(sys.argv[1], {}).items():
            data.setdefault(sys.argv[1], {}).setdefault(k, {}).update(v if isinstance(v, dict) else {})
t = data.get(sys.argv[1], {})
print("\n".join(k for k in t if isinstance(t[k], dict)))
PY
}

# plugin_names — supports the current metadata-rich entries and legacy string entries
# in config.local.toml, keeping old per-box overlays compatible.
plugin_names() {
  cfg plugins.enabled | python3 -c '
import json, sys
for item in json.load(sys.stdin):
    print(item["name"] if isinstance(item, dict) else item)
'
}

skill_providers() {
  local value
  value=$(cfg "skills.$1.providers")
  if [ -z "$value" ]; then printf '%s\n' claude
  else printf '%s' "$value" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)))'
  fi
}

skill_link_path() {
  case "$1" in
    claude) printf '%s' "$CLAUDE_DIR/skills/$2" ;;
    codex)  printf '%s' "$HOME/.agents/skills/$2" ;;
    *) return 1 ;;
  esac
}

requirements_met() {
  local path="$1" value app
  value=$(cfg "$path.requires_apps")
  [ -z "$value" ] && return 0
  for app in $(printf '%s' "$value" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)))'); do
    [ "$(cfg "apps.$app.enabled")" = "true" ] || return 1
  done
}

tool_ready() {
  local bin="$1" check="$2"
  command -v "$bin" >/dev/null 2>&1 || return 1
  [ -z "$check" ] || eval "$check"
}

agent_context_active() {
  PYTHONDONTWRITEBYTECODE=1 python3 "$DOTFILES/scripts/render-agent-integrations.py" --active
}

stow_requirements_met() {
  local package="$1" value tool
  value=$(cfg "stow.$package.requires_tools")
  [ -z "$value" ] && return 0
  for tool in $(printf '%s' "$value" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)))'); do
    [ "$(cfg "tools.$tool.enabled")" = "true" ] || return 1
  done
}

# Verify every declared destination is a symlink to the matching file in its package.
# Python keeps this portable: macOS does not provide GNU `readlink -f` by default.
stow_package_ready() {
  local id="$1" package="$2" target="$3" links
  links=$(cfg "stow.$id.links")
  [ -n "$links" ] || return 1
  STOW_ROOT="$DOTFILES/stow" PACKAGE="$package" TARGET="$target" LINKS="$links" python3 - <<'PY'
import json, os
from pathlib import Path

root = Path(os.environ["STOW_ROOT"]) / os.environ["PACKAGE"]
target = Path(os.environ["TARGET"])
for relative in json.loads(os.environ["LINKS"]):
    source = root / relative
    destination = target / relative
    if not source.exists() or not destination.is_symlink():
        raise SystemExit(1)
    if destination.resolve() != source.resolve():
        raise SystemExit(1)
PY
}

# ── JSON editors for settings.json / .mcp.json (via python, safe) ─────────────
plugin_set() { # plugin_set <name> <true|false>
  CLAUDE_DIR="$CLAUDE_DIR" python3 - "$1" "$2" <<'PY'
import os, json, sys
p = os.path.join(os.environ["CLAUDE_DIR"], "settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("enabledPlugins", {})[sys.argv[1]] = (sys.argv[2] == "true")
json.dump(d, open(p,"w"), indent=2)
PY
}
mcp_set() { # mcp_set <name> <bin> <enabled>
  CLAUDE_DIR="$CLAUDE_DIR" python3 - "$1" "$2" "$3" <<'PY'
import os, json, sys
p = os.path.join(os.environ["CLAUDE_DIR"], ".mcp.json")
d = json.load(open(p)) if os.path.exists(p) else {"mcpServers":{}}
d.setdefault("mcpServers", {})
name, binp, enabled = sys.argv[1], sys.argv[2], sys.argv[3]=="true"
if enabled: d["mcpServers"][name] = {"command": binp}
else: d["mcpServers"].pop(name, None)
json.dump(d, open(p,"w"), indent=2)
PY
}
hook_set() { # hook_set <id> <script-path> <enabled>  — inject on SessionStart+UserPromptSubmit
  CLAUDE_DIR="$CLAUDE_DIR" python3 - "$1" "$2" "$3" <<'PY'
import os, json, sys
p = os.path.join(os.environ["CLAUDE_DIR"], "settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
hid, script, enabled = sys.argv[1], sys.argv[2], sys.argv[3]=="true"
cmd = f"bash {script}"
base = os.path.basename(script)   # match by script name, not full path — survives path changes
hooks = d.setdefault("hooks", {})
def strip(evt):  # remove any prior entry for this hook (by script basename — no dup on path change)
    hooks[evt] = [h for h in hooks.get(evt, [])
                  if not any(base in x.get("command","") for x in h.get("hooks", []))]
    if not hooks[evt]: hooks.pop(evt, None)
strip("SessionStart"); strip("UserPromptSubmit")
if enabled:
    hooks.setdefault("SessionStart", []).append(
        {"matcher": "startup|resume|clear|compact",
         "hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
    hooks.setdefault("UserPromptSubmit", []).append(
        {"hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
json.dump(d, open(p, "w"), indent=2)
PY
}
cmd_hook_set() { # cmd_hook_set <event> <matcher> <command> <enabled> — single event hook
  CLAUDE_DIR="$CLAUDE_DIR" python3 - "$1" "$2" "$3" "$4" <<'PY'
import os, json, sys
p = os.path.join(os.environ["CLAUDE_DIR"], "settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
evt, matcher, cmd, enabled = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]=="true"
hooks = d.setdefault("hooks", {})
hooks[evt] = [h for h in hooks.get(evt, [])
              if not any(cmd == x.get("command") for x in h.get("hooks", []))]
if enabled:
    entry = {"hooks": [{"type": "command", "command": cmd}]}
    if matcher: entry = {"matcher": matcher, **entry}
    hooks[evt].append(entry)
if not hooks[evt]: hooks.pop(evt, None)
json.dump(d, open(p, "w"), indent=2)
PY
}

statusline_set() { # statusline_set <command> <refreshInterval> <padding> <enabled>
  CLAUDE_DIR="$CLAUDE_DIR" python3 - "$1" "$2" "$3" "$4" <<'PY'
import os, json, sys
p = os.path.join(os.environ["CLAUDE_DIR"], "settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
cmd, refresh, padding, enabled = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"
if enabled:
    sl = {"type": "command", "command": cmd}
    if refresh: sl["refreshInterval"] = int(refresh)
    if padding: sl["padding"] = int(padding)
    d["statusLine"] = sl
else:
    d.pop("statusLine", None)
json.dump(d, open(p, "w"), indent=2)
PY
}
cron_set() { # cron_set <id> <schedule> <script> <enabled> — marker-tagged crontab line
  local id="$1" sched="$2" script="$3" enabled="$4" marker="# dotfiles:$1" cur
  cur=$(crontab -l 2>/dev/null | grep -vF "$marker" || true)
  { printf '%s\n' "$cur"
    if [ "$enabled" = "true" ]; then printf '%s %s >> %s 2>&1 %s\n' \
      "$sched" "$script" "$XDG_STATE/dotfiles-$id.log" "$marker"; fi
  } | sed '/^$/d' | crontab -
}

# verify_all — re-check every enabled entry actually landed. Returns nonzero on failure.
verify_all() {
  local fail=0 a t s h c d p name bin tgt link script cmd probe probe_raw cfg_dest want_os label port shell rc shell_cmd check auth_check auth_hint cli app_ok provider package target
  ok()  { say "✓ $*"; }
  bad() { say "✗ $*"; fail=1; }
  for a in $(section_keys apps); do
    [ "$(cfg "apps.$a.enabled")" = "true" ] || continue
    probe_raw=$(cfg "apps.$a.probe_$OS")
    if [ -z "$probe_raw" ]; then bad "app $a unsupported on $OS"; continue; fi
    case "$probe_raw" in
      COMMAND:*) command -v "${probe_raw#COMMAND:}" >/dev/null 2>&1 && app_ok=true || app_ok=false ;;
      *) probe=$(resolve "$probe_raw"); [ -e "$probe" ] && app_ok=true || app_ok=false ;;
    esac
    $app_ok && ok "app $a installed" || bad "app $a missing"
    cli=$(cfg "apps.$a.cli")
    [ -z "$cli" ] || { command -v "$cli" >/dev/null 2>&1 && ok "$a CLI on PATH" || bad "$a CLI missing: $cli"; }
  done
  for t in $(section_keys tools); do
    want_os=$(cfg "tools.$t.os")
    [ -z "$want_os" ] || [ "$want_os" = "$OS" ] || { say "· $t: $want_os-only (n/a on $OS)"; continue; }
    [ "$(cfg "tools.$t.enabled")" = "true" ] || continue
    bin=$(cfg "tools.$t.bin"); bin=$(resolve "${bin:-$t}")
    check=$(cfg "tools.$t.verify_command")
    if tool_ready "$bin" "$check"; then
      ok "tool $t available"
      auth_check=$(cfg "tools.$t.auth_check")
      auth_hint=$(cfg "tools.$t.auth_hint")
      [ -z "$auth_check" ] || { eval "$auth_check" && ok "$t authenticated" || say "⚠ $t: unauthenticated; $auth_hint"; }
    else
      bad "tool $t missing or failed its probe"
    fi
    shell_cmd=$(cfg "tools.$t.shell_command"); shell_cmd=${shell_cmd:-$t}
    for shell in $(cfg "tools.$t.shells" | python3 -c 'import sys,json; v=json.load(sys.stdin); print("\n".join(v))' 2>/dev/null || true); do
      rc=$(shell_rc "$shell") || { bad "tool $t has unsupported shell: $shell"; continue; }
      if command -v "$shell" >/dev/null 2>&1 || [ -f "$rc" ]; then
        grep -qF "# >>> dotfiles:$t >>>" "$rc" 2>/dev/null \
          && ok "tool $t initialized in $rc" || bad "tool $t missing shell init in $rc"
      fi
    done
    cfg_dest=$(cfg "tools.$t.config_dest"); cfg_dest=$(resolve "$cfg_dest")
    [ -z "$cfg_dest" ] || { [ -f "$cfg_dest" ] && ok "config $cfg_dest" || bad "config missing: $cfg_dest"; }
    req=$(cfg "tools.$t.requires_file"); req=$(resolve "$req")
    [ -z "$req" ] || [ -f "$req" ] || say "⚠ $t: $req missing (not fatal, but $t's worker model is dead)"
  done
  for p in $(section_keys stow); do
    [ "$(cfg "stow.$p.enabled")" = "true" ] || continue
    if ! stow_requirements_met "$p"; then
      say "· stow package $p inactive (required tool disabled)"
      continue
    fi
    package=$(cfg "stow.$p.package"); package=${package:-$p}
    target=$(resolve "$(cfg "stow.$p.target")"); target=${target:-$HOME}
    if stow_package_ready "$p" "$package" "$target"; then
      ok "stow package $p linked into $target"
    else
      bad "stow package $p missing, conflicted, or linked to the wrong source"
    fi
  done
  # Daemons: the endpoint answering is the only proof that matters. A loaded-but-dead
  # LaunchAgent is worse than an absent one, because every local job silently escalates.
  for d in $(section_keys daemons); do
    want_os=$(cfg "daemons.$d.os")
    [ -z "$want_os" ] || [ "$want_os" = "$OS" ] || { say "· $d: $want_os-only (n/a on $OS)"; continue; }
    [ "$(cfg "daemons.$d.enabled")" = "true" ] || continue
    label=$(cfg "daemons.$d.label"); port=$(cfg "daemons.$d.port")
    [ -f "$HOME/Library/LaunchAgents/$label.plist" ] \
      && ok "daemon $d plist installed" || bad "daemon $d plist missing: ~/Library/LaunchAgents/$label.plist"
    if curl -sf -m 3 "http://127.0.0.1:$port/v1/models" >/dev/null 2>&1; then
      ok "daemon $d answering on :$port"
    else
      bad "daemon $d NOT answering on :$port — local lane is dead (check $XDG_STATE/local-model.log)"
    fi
  done
  for s in $(section_keys skills); do
    [ "$(cfg "skills.$s.enabled")" = "true" ] || continue
    requirements_met "skills.$s" || { say "· $s: inactive (required app disabled)"; continue; }
    case "$(cfg "skills.$s.type")" in
      plugin)
        name=$(cfg "skills.$s.plugin")
        python3 -c "import json;d=json.load(open('$CLAUDE_DIR/settings.json'));exit(0 if d.get('enabledPlugins',{}).get('$name') else 1)" 2>/dev/null \
          && ok "plugin $name enabled" || bad "plugin $name not enabled in settings.json"
        [ -d "$CLAUDE_DIR/plugins/cache/${name#*@}/${name%%@*}" ] \
          && ok "plugin $name installed" || bad "plugin $name enabled but not installed (cache/${name#*@}/${name%%@*} missing)" ;;
      npx-plugin)
        probe=$(cfg "skills.$s.probe"); probe=$(resolve "$probe")
        [ -z "$probe" ] && { say "· $s: no probe configured (skip)"; continue; }
        [ -e "$probe" ] && ok "$s at $probe" || bad "$s missing: $probe" ;;
      mcp)
        name=$(cfg "skills.$s.mcp"); bin=$(cfg "skills.$s.bin"); bin=$(resolve "$bin")
        [ -x "$bin" ] && ok "mcp binary $bin" || bad "mcp binary missing: $bin"
        python3 -c "import json;d=json.load(open('$CLAUDE_DIR/.mcp.json'));exit(0 if '$name' in d.get('mcpServers',{}) else 1)" 2>/dev/null \
          && ok "mcp $name registered" || bad "mcp $name not in .mcp.json"
        check=$(cfg "skills.$s.verify_command")
        [ -z "$check" ] || { eval "$check" && ok "$s configured" || bad "$s configuration check failed"; } ;;
      symlink)
        for provider in $(skill_providers "$s"); do
          link=$(skill_link_path "$provider" "$s") || { bad "$s has unsupported provider: $provider"; continue; }
          [ -e "$link" ] && ok "skill link $s ($provider)" || bad "skill link broken/missing: $link"
        done ;;
    esac
  done
  for h in $(section_keys hooks); do
    [ "$(cfg "hooks.$h.enabled")" = "true" ] || continue
    cmd=$(cfg "hooks.$h.command"); cmd=$(resolve "$cmd")
    if [ -z "$cmd" ]; then script=$(cfg "hooks.$h.script"); cmd="bash $(resolve "$script")"; fi
    python3 -c "
import json,sys
d=json.load(open('$CLAUDE_DIR/settings.json'))
found=any('$cmd'==x.get('command') for v in d.get('hooks',{}).values() for e in v for x in e.get('hooks',[]))
sys.exit(0 if found else 1)" 2>/dev/null \
      && ok "hook $h wired" || bad "hook $h not wired in settings.json"
  done
  if [ "$(cfg statusline.enabled)" = "true" ]; then
    sl_cmd="bash $(resolve "$(cfg statusline.script)")"
    python3 -c "import json;d=json.load(open('$CLAUDE_DIR/settings.json'));exit(0 if d.get('statusLine',{}).get('command')=='$sl_cmd' else 1)" 2>/dev/null \
      && ok "statusline wired" || bad "statusline not wired in settings.json"
  fi
  for name in $(plugin_names); do
    [ -d "$CLAUDE_DIR/plugins/cache/${name#*@}/${name%%@*}" ] \
      && ok "stock plugin $name installed" || bad "stock plugin $name not installed"
  done
  for c in $(section_keys cron); do
    [ "$(cfg "cron.$c.enabled")" = "true" ] || continue
    crontab -l 2>/dev/null | grep -qF "# dotfiles:$c" && ok "cron $c" || bad "cron $c missing from crontab"
  done
  grep -qF "@$DOTFILES/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null \
    && ok "global CLAUDE.md points at hub" || bad "global CLAUDE.md not pointing at hub"
  [ -s "$DOTFILES/agent-integrations.local.md" ] \
    && ok "agent integrations rendered" || bad "agent-integrations.local.md missing/empty — run setup"
  if agent_context_active; then
    grep -qF '<!-- >>> dotfiles:agent-integrations >>> -->' "$CODEX_DIR/AGENTS.md" 2>/dev/null \
      && ok "global Codex AGENTS.md has integrations" || bad "global Codex AGENTS.md missing integration block"
  elif grep -qF '<!-- >>> dotfiles:agent-integrations >>> -->' "$CODEX_DIR/AGENTS.md" 2>/dev/null; then
    bad "global Codex AGENTS.md has disabled integration block"
  fi
  [ -f "$DOTFILES/config.local.toml" ] && ok "config.local.toml overlay present" \
    || say "· no config.local.toml (base defaults apply — copy configs/config.local.example.toml to override per-box)"
  [ -s "$DOTFILES/routing.local.md" ] && ok "routing.local.md rendered" || bad "routing.local.md missing/empty — run setup"
  "$DOTFILES/scripts/render-readme-catalog.py" --check \
    && ok "README add-on catalog matches config.toml" || bad "README add-on catalog stale — run scripts/render-readme-catalog.py"
  return $fail
}

# ─────────────────────────────────────────────────────────────────────────────
if $VERIFY_ONLY; then
  head "dotfiles verify"
  verify_all && { head "all good"; exit 0; } || { head "FAILURES above"; exit 1; }
fi

head "dotfiles setup$DRY_LABEL"

# 0. Prerequisites (fail early with one clear list, not five cryptic errors later).
head "prerequisites"
MISSING=""
for p in git curl crontab; do command -v "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"; done
command -v npx    >/dev/null 2>&1 || MISSING="$MISSING node/npx"
command -v claude >/dev/null 2>&1 || MISSING="$MISSING claude(-code)"
if [ -n "$MISSING" ]; then
  say "⚠ missing:$MISSING — install these first; continuing, but dependent steps will fail"
else
  say "✓ git curl crontab npx claude"
fi

# 1. Desktop apps. Installers own only the app and companion CLI; disabling retains
# application data and binaries, matching the non-destructive tool toggle policy.
head "apps"
for a in $(section_keys apps); do
  enabled=$(cfg "apps.$a.enabled")
  if [ "$enabled" != "true" ]; then say "$a: disabled (app and data retained)"; continue; fi
  probe_raw=$(cfg "apps.$a.probe_$OS")
  if [ -z "$probe_raw" ]; then say "$a: ⚠ unsupported on $OS"; continue; fi
  case "$probe_raw" in
    COMMAND:*) command -v "${probe_raw#COMMAND:}" >/dev/null 2>&1 && app_ok=true || app_ok=false ;;
    *) probe=$(resolve "$probe_raw"); [ -e "$probe" ] && app_ok=true || app_ok=false ;;
  esac
  cli=$(cfg "apps.$a.cli")
  if $app_ok && { [ -z "$cli" ] || command -v "$cli" >/dev/null 2>&1; }; then
    say "$a: ✓ app + CLI installed"
  else
    inst=$(cfg "apps.$a.install")
    if [ -n "$inst" ]; then run "$inst"; say "$a: installer completed"
    else say "$a: ⚠ missing and no install command"; fi
  fi
done

# 2. Render cross-app agent guidance and expose the same effective configuration to
# Claude and Codex. Claude supports @ imports; Codex receives a marker-owned block so
# existing global instructions remain intact.
head "agent integrations"
if $DRY; then
  say "would: render merged integrations -> agent-integrations.local.md"
  if agent_context_active; then say "would: update managed block in ~/.codex/AGENTS.md"
  else say "would: remove managed block from ~/.codex/AGENTS.md"; fi
else
  "$DOTFILES/scripts/render-agent-integrations.py" > "$DOTFILES/agent-integrations.local.md"
  if agent_context_active; then enabled=true; else enabled=false; fi
  markdown_block_set "$CODEX_DIR/AGENTS.md" agent-integrations \
    "$DOTFILES/agent-integrations.local.md" "$enabled"
  say "rendered; Codex managed block -> enabled=$enabled"
fi

# 2b. Wire global CLAUDE.md -> this hub (idempotent single line).
head "global CLAUDE.md hub"
GLOBAL="$CLAUDE_DIR/CLAUDE.md"
HUB_LINE="@$DOTFILES/CLAUDE.md"
if [ -f "$GLOBAL" ] && grep -qF "$HUB_LINE" "$GLOBAL" 2>/dev/null; then
  say "already points at hub"
else
  run "cp -n '$GLOBAL' '$GLOBAL.pre-dotfiles.bak' 2>/dev/null || true"
  run "printf '# Global Claude Instructions\n\n%s\n' '$HUB_LINE' > '$GLOBAL'"
  say "global -> $HUB_LINE (old content backed up to CLAUDE.md.pre-dotfiles.bak)"
fi

# 3. Tools (PATH binaries; optional owned config file rendered next to it).
head "tools"
if $UPDATE && command -v brew >/dev/null 2>&1; then run "brew upgrade"; fi
for t in $(section_keys tools); do
  enabled=$(cfg "tools.$t.enabled")
  # `bin` override: the entrypoint isn't always named after the key (github-cli -> gh).
  bin=$(cfg "tools.$t.bin"); bin=$(resolve "${bin:-$t}")
  # `os` gate: an entry pinned to another OS is inert here, not a failure.
  want_os=$(cfg "tools.$t.os")
  if [ -n "$want_os" ] && [ "$want_os" != "$OS" ]; then say "$t: $want_os-only (skip on $OS)"; continue; fi
  shell_cmd=$(cfg "tools.$t.shell_command"); shell_cmd=${shell_cmd:-$t}
  init_args=$(cfg "tools.$t.shell_init_args")
  init_verb=$(cfg "tools.$t.shell_init_verb")
  if [ "$enabled" != "true" ]; then
    for shell in $(cfg "tools.$t.shells" | python3 -c 'import sys,json; v=json.load(sys.stdin); print("\n".join(v))' 2>/dev/null || true); do
      rc=$(shell_rc "$shell") || { say "$t: ⚠ unsupported shell '$shell'"; continue; }
      if [ -f "$rc" ]; then run "shell_init_set '$t' '$shell_cmd' '$shell' false"; fi
    done
    say "$t: disabled (shell integration removed; binary retained)"; continue
  fi
  check=$(cfg "tools.$t.verify_command")
  if tool_ready "$bin" "$check" && ! $UPDATE; then
    say "$t: ✓ on PATH"
  else
    inst=$(cfg "tools.$t.install")
    if [ -n "$inst" ]; then run "$inst"; say "$t: $($UPDATE && echo updated || echo installed)"
    else say "$t: ⚠ not on PATH and no install command — install manually"; fi
  fi
  auth_check=$(cfg "tools.$t.auth_check")
  auth_hint=$(cfg "tools.$t.auth_hint")
  if [ -n "$auth_check" ] && tool_ready "$bin" "$check" && ! eval "$auth_check"; then
    say "$t: ⚠ installed but unauthenticated; $auth_hint"
  fi
  # Shell integration is independently marker-owned, so disabling the tool reverses it
  # without overwriting or symlinking the user's wider shell configuration.
  for shell in $(cfg "tools.$t.shells" | python3 -c 'import sys,json; v=json.load(sys.stdin); print("\n".join(v))' 2>/dev/null || true); do
    rc=$(shell_rc "$shell") || { say "$t: ⚠ unsupported shell '$shell'"; continue; }
    if command -v "$shell" >/dev/null 2>&1 || [ -f "$rc" ]; then
      run "shell_init_set '$t' '$shell_cmd' '$shell' true '$init_args' '$init_verb'"
      say "$t: shell init -> $rc"
    else
      say "$t: $shell not installed (shell init skipped)"
    fi
  done
  # owned config file: template in dotfiles, HOME/ rendered, copied to dest
  src=$(cfg "tools.$t.config"); dest=$(cfg "tools.$t.config_dest")
  if [ -n "$src" ] && [ -n "$dest" ]; then
    src=$(resolve "$src"); dest=$(resolve "$dest")
    if [ -f "$src" ]; then
      run "mkdir -p '$(dirname "$dest")'"
      run "sed 's|HOME/|$HOME/|g' '$src' > '$dest'"
      say "$t: config -> $dest"
    else say "$t: ⚠ config template missing ($src) — skip"; fi
  fi
  req=$(cfg "tools.$t.requires_file")
  if [ -n "$req" ]; then req=$(resolve "$req")
    [ -f "$req" ] || say "$t: ⚠ $req missing — create it or $t's worker model won't run"
  fi
  # default_model: ensure just the `model` key in a partly-machine-owned config
  # (codex ~/.codex/config.toml holds trust levels/projects — must NOT clobber).
  dm=$(cfg "tools.$t.default_model")
  if [ -n "$dm" ] && [ "$t" = "codex" ]; then
    if $DRY; then
      say "would: set model = $dm in ~/.codex/config.toml (preserving all other keys)"
    else
      CXP="$HOME/.codex/config.toml" DM="$dm" python3 - <<'PY'
import os, re
p = os.environ["CXP"]; dm = os.environ["DM"]
os.makedirs(os.path.dirname(p), exist_ok=True)
text = open(p).read() if os.path.exists(p) else ""
line = f'model = "{dm}"'
if re.search(r'(?m)^\s*model\s*=', text):
    text = re.sub(r'(?m)^\s*model\s*=.*$', line, text, count=1)
else:
    text = line + "\n" + text
open(p, "w").write(text)
PY
      say "$t: default model = $dm"
    fi
  fi
done

# 3b. Complete, repo-owned config files. Stow is an implementation detail: setup owns
# reconciliation and uses --no-folding so packages can safely share ~/.config later.
head "stow packages"
for p in $(section_keys stow); do
  enabled=$(cfg "stow.$p.enabled")
  package=$(cfg "stow.$p.package"); package=${package:-$p}
  target=$(resolve "$(cfg "stow.$p.target")"); target=${target:-$HOME}
  source="$DOTFILES/stow/$package"
  if [ "$enabled" = "true" ] && ! stow_requirements_met "$p"; then
    enabled=false
    say "$p: required tool disabled; deactivating links"
  fi
  if [ "$enabled" = "true" ]; then
    [ -d "$source" ] || { say "$p: ⚠ package directory missing ($source)"; continue; }
    if stow_package_ready "$p" "$package" "$target"; then
      say "$p: ✓ linked into $target"
    elif $DRY; then
      say "would: stow --simulate --no-folding --restow --dir='$DOTFILES/stow' --target='$target' '$package'"
    elif command -v stow >/dev/null 2>&1; then
      stow --no-folding --restow --dir="$DOTFILES/stow" --target="$target" "$package"
      say "$p: linked into $target"
    else
      say "$p: ⚠ GNU Stow unavailable; links not changed"
    fi
  elif $DRY; then
    say "would: unstow $package from $target if currently linked"
  elif command -v stow >/dev/null 2>&1; then
    stow --no-folding --delete --dir="$DOTFILES/stow" --target="$target" "$package"
    say "$p: disabled (repo-owned links removed)"
  else
    say "$p: disabled; GNU Stow unavailable, so existing links were retained"
  fi
done

# 4. Skills.
head "skills"
for s in $(section_keys skills); do
  enabled=$(cfg "skills.$s.enabled"); type=$(cfg "skills.$s.type")
  if [ "$enabled" = "true" ] && ! requirements_met "skills.$s"; then
    enabled=false
    say "$s: required app disabled; deactivating wiring"
  fi
  case "$type" in
    plugin)
      name=$(cfg "skills.$s.plugin"); mkt=$(cfg "skills.$s.marketplace")
      if [ "$enabled" = "true" ] && [ -n "$mkt" ]; then
        run "claude plugin marketplace add '$mkt' 2>/dev/null || true"
        run "claude plugin install '$name' 2>/dev/null || true"
      fi
      run "plugin_set '$name' '$enabled'"
      say "$s: plugin $name -> enabled=$enabled${mkt:+ (mkt: $mkt)}" ;;
    npx-plugin)
      if [ "$enabled" = "true" ]; then
        probe=$(resolve "$(cfg "skills.$s.probe")")
        if [ -n "$probe" ] && [ -e "$probe" ]; then say "$s: ✓ already at $probe"
        else inst=$(cfg "skills.$s.install"); run "$inst"; say "$s: installed via $inst"; fi
      else say "$s: disabled (npx-plugin — remove ~/.claude/plugins/$s manually)"; fi ;;
    mcp)
      name=$(cfg "skills.$s.mcp"); bin=$(resolve "$(cfg "skills.$s.bin")")
      if [ "$enabled" = "true" ] && ! command -v "$bin" >/dev/null 2>&1; then
        inst=$(cfg "skills.$s.install")
        if [ -n "$inst" ]; then
          run "$inst"; say "$s: installed"
          bin=$(resolve "$(cfg "skills.$s.bin")")   # COMMAND: resolves now that it's on PATH
        else say "$s: ⚠ binary missing ($bin) and no install command"; fi
      fi
      run "mcp_set '$name' '$bin' '$enabled'"
      configure=$(cfg "skills.$s.configure")
      if [ "$enabled" = "true" ] && [ -n "$configure" ]; then
        run "$configure"
        say "$s: runtime configuration applied"
      fi
      say "$s: mcp $name -> enabled=$enabled" ;;
    symlink)
      tgt=$(resolve "$(cfg "skills.$s.target")")
      if [ "$enabled" = "true" ]; then
        if [ -e "$tgt" ]; then
          for provider in $(skill_providers "$s"); do
            link=$(skill_link_path "$provider" "$s") || { say "$s: ⚠ unsupported provider '$provider'"; continue; }
            run "mkdir -p '$(dirname "$link")'"; run "ln -sfn '$tgt' '$link'"
            say "$s: linked for $provider -> $tgt"
          done
        else say "$s: ⚠ target missing ($tgt) — skip"; fi
      else
        for provider in claude codex; do
          link=$(skill_link_path "$provider" "$s")
          run "rm -f '$link'"
        done
        say "$s: unlinked"
      fi ;;
    *) say "$s: unknown type '$type' — skip" ;;
  esac
done

# 3b. Hooks — `command` entries wire on their event; `script` entries inject every turn.
head "hooks"
for h in $(section_keys hooks); do
  enabled=$(cfg "hooks.$h.enabled"); cmd=$(cfg "hooks.$h.command")
  if [ -n "$cmd" ]; then
    event=$(cfg "hooks.$h.event"); matcher=$(cfg "hooks.$h.matcher")
    cmd=$(resolve "$cmd")          # a command may be a bare binary (rtk) or a DOTFILES/ script
    binword="${cmd%% *}"
    # A DOTFILES/ script must exist and be executable; a bare binary must be on PATH.
    if [ "$enabled" = "true" ]; then
      case "$binword" in
        /*) [ -x "$binword" ] || { say "$h: ⚠ script missing/not executable ($binword) — skip"; continue; } ;;
        *)  command -v "$binword" >/dev/null 2>&1 || { say "$h: ⚠ '$binword' not on PATH — hook would break every $event; skip"; continue; } ;;
      esac
    fi
    run "cmd_hook_set '$event' '$matcher' '$cmd' '$enabled'"
    say "$h: $event hook -> enabled=$enabled"
  else
    script=$(resolve "$(cfg "hooks.$h.script")")
    if [ "$enabled" = "true" ] && [ ! -f "$script" ]; then say "$h: ⚠ script missing ($script) — skip"; continue; fi
    run "hook_set '$h' '$script' '$enabled'"
    say "$h: hook -> enabled=$enabled"
  fi
done

# 3b. Status line (single command, not a keyed section).
head "statusline"
sl_enabled=$(cfg "statusline.enabled")
sl_script=$(resolve "$(cfg "statusline.script")")
if [ "$sl_enabled" = "true" ] && [ ! -f "$sl_script" ]; then
  say "statusline: ⚠ script missing ($sl_script) — skip"
else
  [ "$sl_enabled" = "true" ] && run "chmod +x '$sl_script'"
  run "statusline_set 'bash $sl_script' '$(cfg statusline.refresh)' '$(cfg statusline.padding)' '$sl_enabled'"
  say "statusline -> enabled=$sl_enabled"
fi

# 4. Stock plugins (install from the official marketplace + enable).
head "plugins"
run "claude plugin marketplace add anthropics/claude-plugins-official 2>/dev/null || true"
for name in $(plugin_names); do
  run "claude plugin install '$name' 2>/dev/null || true"
  run "plugin_set '$name' 'true'"
  say "$name: installed+enabled"
done

# 4c. Daemons (launchd LaunchAgents; macOS-only — inert elsewhere).
# The plist template carries LABEL/PROGRAM_ARGS/MODEL/PORT placeholders; the ProgramArgs
# are built from `runtime` (currently llama-server only) without touching anything
# downstream (it serves OpenAI-compatible on the same port).
head "daemons"
for d in $(section_keys daemons); do
  want_os=$(cfg "daemons.$d.os")
  if [ -n "$want_os" ] && [ "$want_os" != "$OS" ]; then say "$d: $want_os-only (skip on $OS)"; continue; fi
  enabled=$(cfg "daemons.$d.enabled")
  label=$(cfg "daemons.$d.label")
  agent="$HOME/Library/LaunchAgents/$label.plist"
  if [ "$enabled" != "true" ]; then
    run "launchctl bootout gui/\$(id -u)/'$label' 2>/dev/null || true"
    run "rm -f '$agent'"
    say "$d: disabled (unloaded)"; continue
  fi
  tmpl=$(resolve "$(cfg "daemons.$d.plist")")
  model=$(resolve "$(cfg "daemons.$d.model")")
  port=$(cfg "daemons.$d.port"); runtime=$(cfg "daemons.$d.runtime")
  [ -f "$tmpl" ] || { say "$d: ⚠ plist template missing ($tmpl) — skip"; continue; }
  # Auto-provision the weights: download the configured HF gguf if absent (aria2 multi-conn,
  # curl fallback), then point the `model` symlink at it. Resumes partial downloads; only
  # symlinks once complete (no leftover .aria2 control file). Swap models via config + re-run.
  mrepo=$(cfg "daemons.$d.model_repo"); mfile=$(cfg "daemons.$d.model_file")
  if [ -n "$mrepo" ] && [ -n "$mfile" ]; then
    mdir=$(dirname "$model"); target="$mdir/$mfile"; murl="https://huggingface.co/$mrepo/resolve/main/$mfile"
    run "mkdir -p '$mdir'"
    if [ ! -f "$target" ] || [ -f "$target.aria2" ]; then
      say "$d: fetching $mfile (large — first run only)"
      if command -v aria2c >/dev/null 2>&1; then
        run "aria2c -c -x16 -s16 -j16 --file-allocation=none --console-log-level=warn -d '$mdir' -o '$mfile' '$murl'"
      else
        run "curl -L --fail -C - -o '$target' '$murl'"
      fi
    fi
    if [ -f "$target.aria2" ]; then say "$d: ⚠ $mfile download incomplete — re-run setup to resume"
    else run "ln -sfn '$target' '$model'"; say "$d: model -> $mfile"; fi
  fi
  [ -e "$model" ] || say "$d: ⚠ $model missing — symlink it at a real GGUF model or the daemon idles broken"

  # Per-runtime argv. Every flag here is load-bearing; see config.toml [daemons] for why.
  case "$runtime" in
    llama-server)
      args="    <string>$(command -v llama-server || echo /opt/homebrew/bin/llama-server)</string>
    <string>--model</string><string>$model</string>
    <string>--alias</string><string>local</string>
    <string>--jinja</string>
    <string>--reasoning-format</string><string>deepseek</string>
    <string>--ctx-size</string><string>32768</string>
    <string>--port</string><string>$port</string>
    <string>--host</string><string>127.0.0.1</string>
    <string>--flash-attn</string><string>on</string>
    <string>--cache-type-k</string><string>q8_0</string>
    <string>--cache-type-v</string><string>q8_0</string>
    <string>--cache-ram</string><string>32768</string>
    <string>--parallel</string><string>2</string>
    <string>--sleep-idle-seconds</string><string>600</string>" ;;
    *) say "$d: ⚠ unknown runtime '$runtime' (want llama-server) — skip"; continue ;;
  esac

  run "mkdir -p '$HOME/Library/LaunchAgents' '$XDG_STATE'"
  if $DRY; then say "would: render $tmpl -> $agent (runtime=$runtime) + bootstrap"
  else
    ARGS="$args" LABEL="$label" MODEL="$model" PORT="$port" HOMEDIR="$HOME" \
      python3 - "$tmpl" "$agent" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
text = text.replace("PROGRAM_ARGS", os.environ["ARGS"])
text = text.replace("LABEL", os.environ["LABEL"])
text = text.replace("HOME/", os.environ["HOMEDIR"] + "/")
open(dst, "w").write(text)
PY
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    # bootout is async — wait for teardown so the re-bootstrap doesn't race (else it fails
    # "already loaded" and the daemon keeps the stale plist, ignoring config changes).
    for _ in 1 2 3 4 5; do launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || break; sleep 1; done
    launchctl bootstrap "gui/$(id -u)" "$agent" 2>/dev/null || \
      say "$d: ⚠ launchctl bootstrap failed — check $XDG_STATE/local-model.log"
  fi
  say "$d: $runtime -> 127.0.0.1:$port (idle-unloads; model = $model)"
done

# 4b. Cron entries (marker-tagged, idempotent — remove on disable).
head "cron"
for c in $(section_keys cron); do
  enabled=$(cfg "cron.$c.enabled"); sched=$(cfg "cron.$c.schedule")
  script=$(resolve "$(cfg "cron.$c.script")")
  if [ "$enabled" = "true" ] && [ ! -f "$script" ]; then say "$c: ⚠ script missing ($script) — skip"; continue; fi
  run "mkdir -p '$XDG_STATE'"
  run "cron_set '$c' '$sched' '$script' '$enabled'"
  say "$c: cron '$sched' -> enabled=$enabled"
done

# 5. Render routing.local.md (gitignored) from merged config — CLAUDE.md @-imports it.
# Same renderer as the routing hook, so the file and the banner can never disagree.
head "routing"
run "bash '$DOTFILES/hooks/routing-activate.sh' > '$DOTFILES/routing.local.md'"
say "routing.local.md rendered (gitignored, imported by CLAUDE.md)"

# 6. Verify everything enabled actually landed.
if $DRY; then
  head "done (dry-run — nothing changed, verify skipped)"
else
  head "verify"
  if verify_all; then head "done — all good"
  else head "done — WITH FAILURES (see ✗ above)"; exit 1; fi
fi
say "restart active Claude/Codex/T3 sessions to pick up instruction and MCP changes."
