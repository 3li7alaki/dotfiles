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
DOTFILES="$(dirname "$CONFIG")"

# The banner below is live: it probes each engine's endpoint, so local-model state changes
# without anyone editing config. Claude sees that freshness through this injection, but the
# copy Codex and opencode read is a file, and a file is only as accurate as its last write.
# So after printing, persist the same text and re-sync the harness blocks from it. Both are
# no-ops when nothing changed, and both are best-effort: a routing refresh must never be
# the reason a prompt fails.
refresh_global_context() {
  printf '%s\n' "$1" > "$DOTFILES/routing.local.md" 2>/dev/null || return 0
  "$DOTFILES/scripts/render-global-context.py" --install --quiet >/dev/null 2>&1 || true
}

BANNER="$(CONFIG="$CONFIG" python3 <<'PY'
import os, tomllib
d = tomllib.load(open(os.environ["CONFIG"], "rb"))
local = os.environ["CONFIG"].replace("config.toml", "config.local.toml")
if os.path.exists(local):
    def deep(dst, src):
        for k, v in src.items():
            if isinstance(v, dict) and isinstance(dst.get(k), dict): deep(dst[k], v)
            else: dst[k] = v
    deep(d, tomllib.load(open(local, "rb")))
r = d.get("routing", {}); e = d.get("engines", {}); pools = d.get("pools", {})
labels = {"heavy": "hard / agentic / multi-file coding — the flagship",
          "bulk": "routine clear-spec implementation, migrations",
          "mechanical": "cheap / mechanical edits, data munging (GLM coding plan — spread load)",
          "ui": "user-facing (UI, copy, API) — needs taste",
          "review": "plan / implementation review",
          "private": "data/diff must NOT leave the box (NDA, secrets, client code)",
          "verify": "ASYNC closed-question checks (mint's anti-gaming lens, secret scan)"}
print("MODEL ROUTING ACTIVE — dispatch by task shape, don't do everything as raw Claude.")
# Pools come from [pools]: plan size sets THROUGHPUT, so the capacity line for the plan
# currently on file is the one that tells the agent how freely to spend that pool.
if pools:
    print("Flat pools (~0 marginal cost — pick on intelligence/taste + spread cap load, not price):")
    for name, p in pools.items():
        plan = p.get("plan", "?")
        print(f"  {name} [{plan}]: " + ", ".join(p.get("models", [])))
        note = p.get("capacity", {}).get(plan)
        if note: print(f"      {note}")
    print()
else:
    print("All flat, ~0 marginal cost: pick on intelligence/taste + spread cap load, not price.\n")
for k in ("heavy", "bulk", "mechanical", "ui", "review", "private", "verify"):
    if k in r: print(f"- {labels.get(k,k)} -> {r[k]}")
active = [name for name, cfg in e.items() if cfg.get("active")]
# Liveness: an engine with requires_endpoint is only usable if that endpoint answers now.
# localhost-refused returns instantly, so this adds no latency when the local model is off.
# Assert the payload, not just a 200: another local service on the same port (a dev server
# bound to the IPv6 wildcard, say) will happily answer /health and masquerade as the model.
import urllib.request
def _up(url, t=2.0):
    try:
        with urllib.request.urlopen(url, timeout=t) as r:
            return b'"status":"ok"' in r.read(256).replace(b", ", b",")
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
)"

printf '%s\n' "$BANNER"
refresh_global_context "$BANNER"
