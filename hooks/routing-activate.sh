#!/usr/bin/env bash
# Routing injector (SessionStart + UserPromptSubmit).
# Renders the current [routing]/[engines] from config.toml into attention so the
# agent actually dispatches work to the right worker (codex/opencode-glm) instead
# of doing everything as raw Claude. Ponytail pattern: always-on, no blocking.
#
# Source of truth is config.toml + per-box config.local.toml overlay (local wins).
# This is THE routing surface — nothing routing-related is rendered into committed files.

CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.toml"
[ -f "$CONFIG" ] || exit 0

CONFIG="$CONFIG" python3 <<'PY'
import os, tomllib
d = tomllib.load(open(os.environ["CONFIG"], "rb"))
local = os.environ["CONFIG"].replace("config.toml", "config.local.toml")
if os.path.exists(local):
    def deep(dst, src):
        for k, v in src.items():
            if isinstance(v, dict) and isinstance(dst.get(k), dict): deep(dst[k], v)
            else: dst[k] = v
    deep(d, tomllib.load(open(local, "rb")))
r = d.get("routing", {}); e = d.get("engines", {})
labels = {"heavy": "hard / agentic / multi-file coding — the flagship",
          "bulk": "routine clear-spec implementation, migrations",
          "mechanical": "cheap / mechanical edits, data munging (GLM coding plan — spread load)",
          "ui": "user-facing (UI, copy, API) — needs taste",
          "review": "plan / implementation review",
          "private": "data/diff must NOT leave the box (NDA, secrets, client code)",
          "verify": "ASYNC closed-question checks (mint's anti-gaming lens, secret scan)"}
print("MODEL ROUTING ACTIVE — dispatch by task shape, don't do everything as raw Claude.")
print("Three flat pools (Claude Max 5x: opus/fable · ChatGPT Pro: sol/terra/luna · GLM coding plan: glm-5.2).")
print("All flat, ~0 marginal cost: pick on intelligence/taste + spread cap load, not price.\n")
for k in ("heavy", "bulk", "mechanical", "ui", "review", "private", "verify"):
    if k in r: print(f"- {labels.get(k,k)} -> {r[k]}")
active = [name for name, cfg in e.items() if cfg.get("active")]
# Liveness: an engine with requires_endpoint is only usable if that endpoint answers now.
# localhost-refused returns instantly, so this adds no latency when the local model is off.
import urllib.request
def _up(url, t=0.5):
    try: urllib.request.urlopen(url, timeout=t); return True
    except Exception: return False
down = []
for name in list(active):
    ep = e[name].get("requires_endpoint")
    if ep and not _up(ep.rsplit("/v1", 1)[0] + "/health"):
        active.remove(name); down.append(name)
print("\nExternal workers you can dispatch to (run via Bash):")
for name in active:
    print(f"  {name}: {e[name]['run']}")
if r.get("fallback"):
    print("\nOn a rate-limit (429): fall back " + " then ".join(r["fallback"]) + ", then escalate. Don't just stall.")
# Codex dispatch mechanics — only when a codex-backed engine is actually active on this box.
if r.get("codex_usage") and any(name in active for name in ("gpt-5.6-sol", "gpt-5.6-terra")):
    print("\n" + r["codex_usage"].strip())
if "local" in down:
    print("\n⚠ LOCAL model is DOWN (endpoint not answering). Start it with `model on`.")
    print("Until it's up: do NOT route to local. `verify` may degrade to a cloud tier; but")
    print("`private` (must-not-leave-box) work is BLOCKED — ask the user to start the local")
    print("model rather than sending sensitive data to a cloud pool.")
elif "local" in e:
    print("\nThe LOCAL model is ASYNC-ONLY. It is slower than every cloud pool and that is fine —")
    print("nothing waits on it (a hook, a queue, a `done` gate). Never put it in front of the")
    print("user's cursor, and never fall back to it mid-loop: it can't reliably hold a long")
    print("agentic loop, so a fallback trades a clean stall for a silent half-finished diff.")
    print("Use it when the data must not leave the box, or for closed-question verification.")
print("\nClaude-native models (opus/fable) run via the Agent/Workflow model param, no external call.")
PY
