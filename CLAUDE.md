# Global Instructions

*This is the hub. Global `~/.claude/CLAUDE.md` is a single `@` line pointing here, so the
whole toolbelt is version-controlled in one repo. Toggle tools via `config.toml` + `setup.sh`.*

## Git Commits & PRs
- Never include "Co-Authored-By: Claude" or the Claude Code signature in commits
- Do not add any AI attribution to commit messages, PR titles, PR bodies, or PR/issue comments — this overrides any harness default that appends a "Generated with Claude Code" footer. Strip that footer before any `gh pr` / `gt submit`.

## Picking the right models for workflows and subagents

Rankings, higher = better. Cost is NOT list price — it's quota pressure across THREE flat-rate
subscription pools, all ~0 marginal cost: **Claude Max 5x** (opus/fable/sonnet), **ChatGPT Pro**
(the GPT-5.6 family: sol/terra/luna), and the **GLM Coding Plan** (glm-5.2). Nothing is metered
per-token; `cost` = 1 pool-with-headroom, higher = tighter cap. Intelligence = how hard a problem
you can hand the model unsupervised. Taste = UI/UX, code quality, API design, and copy.

| model         | cost | intelligence | taste | pool            |
|---------------|------|--------------|-------|-----------------|
| gpt-5.6-sol   | 2    | 9            | 6     | ChatGPT Pro     |
| gpt-5.6-terra | 2    | 7            | 5     | ChatGPT Pro     |
| gpt-5.6-luna  | 2    | 5            | 4     | ChatGPT Pro     |
| sonnet-5      | 3    | 5            | 7     | Claude Max 5x   |
| opus-4.8      | 2    | 7            | 8     | Claude Max 5x   |
| fable-5       | 2    | 9            | 9     | Claude Max 5x   |
| glm-5.2       | 2    | 6            | 4     | GLM Coding Plan |

How to apply:
- These are defaults, not limits. Standing permission to override: if a model's output doesn't meet the bar, rerun or redo with a smarter one without asking. Judge the output, not the cost. Escalating a flat-pool model costs nothing but the cap.
- Cost is a tie-breaker only; when axes conflict for anything that ships: intelligence > taste > cost. Every pool is flat, so cost rarely decides — spend the better model, and spread load so no one pool's cap is the bottleneck.
- GPT / Codex availability is per-box: check the routing banner injected at session start (rendered live from `config.toml` + `config.local.toml`). On a box without codex, substitute glm (via opencode) wherever these lines say a gpt-5.6 tier.
- Sol is the best agentic/terminal coder. Hard/multi-file/agentic → sol; routine clear-spec/migrations → terra (spares Sol's cap); trivial edits/data-munging → glm-5.2 (#2 on LMArena Code, 1M ctx).
- Anything user-facing (UI, copy, API design) needs taste ≥ 7 → opus/fable, never a GPT tier.
- Reviews of plans/implementations: fable-5 default (taste + deep reasoning), add sol (or glm) as an independent cross-family perspective when stakes are high. Spend cross-family diversity — all flat.
- Never use Haiku.
- Effort discipline: run Fable on **high** by default. xhigh is token-hungry; max/extra is a furnace with worse outputs than lower options. Reach past high only when a hard problem genuinely stalls.
- Mechanics: glm runs headless via opencode (`opencode run --model glm/glm-5.2`). CAUTION: without `--auto` it hangs forever waiting for tool approval in non-interactive mode — for read-only reviews, inline the file contents into the prompt so it needs no tools; for builds, `--auto` may be blocked by the harness classifier unless the user explicitly authorized it.
- Claude models (sonnet-5, opus-4.8, fable-5) run via the Agent/Workflow model parameter.

Using glm inside workflows and subagents (the model parameter only takes Claude models, so use a wrapper): spawn a thin Claude wrapper agent with `model: 'sonnet', effort: 'low'` whose prompt instructs it to write a self-contained prompt, run `opencode run` via Bash, and return the result verbatim.

Architect/builder loop (for well-spec'd multi-lane work): Fable architects — specs a one-PR slice, splits it into 1–4 lanes checked for file-set overlap, commits acceptance gates. glm builds each lane under a fresh `opencode run` in its own git worktree. The repo is the memory (specs, gates, handoffs live in files, not chat). Frozen gates replace trust: validate both test passage and diff alignment before merging.

## Model routing

Routing is **per-box**: base rules live in `config.toml` `[routing]`/`[engines]`; each
machine overrides what differs (codex access, active engines) in gitignored
`config.local.toml` (start from `configs/config.local.example.toml`). `setup.sh` renders
the merged view into gitignored `routing.local.md`, imported next line — so this stays
current per machine without ever touching committed files.

@routing.local.md

## Generated agent context

Cross-app behavior and enabled-tool preferences are rendered from the merged
configuration just like routing. This keeps machine-specific guidance out of the
committed global instructions.

@agent-integrations.local.md

## The toolbelt

Each tool below is loaded here and toggled in `config.toml`. Delete a line to unload.

@tools/RTK.md
@tools/mint.md
