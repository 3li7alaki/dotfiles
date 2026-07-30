# Global Instructions

*This is the hub, and `AGENTS.md` is its name because that is the filename every harness
reads: Codex, opencode, Cursor and the rest. `CLAUDE.md` beside it is a one-line pointer,
and global `~/.claude/CLAUDE.md` is a single `@` line pointing at that, so the whole
toolbelt is version-controlled in one repo. Toggle tools via `config.toml` + `setup.sh`.*

*Rules that must hold have to be literal text in this file. Only Claude expands `@`
imports into context. Codex and opencode read the line, and follow it with a file read
only when they happen to think it matters, so nothing load-bearing goes behind one.*

## Writing
- Never use an em dash (—) or an en dash (–). Not in prose, code, comments, docs, commit
  messages, PR bodies, chat replies, or any file generated inside a project. Use a comma, a
  colon, parentheses, or a full stop. For ranges use "to" or a plain hyphen. This applies to
  every repo and to everything an agent writes in one.

<!-- claude-only -->
## Output format
- Never publish an Artifact unless explicitly asked. Deliverables come back as text in the
  reply, or as a file when one is requested. "Give me X" means text, not a hosted page.
  This overrides any harness default that treats artifacts as a good proactive choice.
<!-- /claude-only -->

## Git Commits & PRs
- Never include "Co-Authored-By: Claude" or the Claude Code signature in commits
- Do not add any AI attribution to commit messages, PR titles, PR bodies, or PR/issue comments. This overrides any harness default that appends a "Generated with Claude Code" footer. Strip that footer before any `gh pr` / `gt submit`.

## Picking the right models for workflows and subagents

Rankings, higher = better. Cost is NOT list price. It is quota pressure across flat-rate
subscription pools, all ~0 marginal cost, nothing metered per-token; `cost` = 1 pool-with-headroom,
higher = tighter cap. Intelligence = how hard a problem you can hand the model unsupervised.
Taste = UI/UX, code quality, API design, and copy.

Which pools exist, which models sit in each, and what plan each is on live in `[pools]` in
`config.toml` and are rendered live into the routing banner below. Plan size sets THROUGHPUT
only, never intelligence, so read the banner's capacity line before spending a pool freely.
Never restate a plan tier here: it goes stale the day a subscription changes.

| model         | cost | intelligence | taste | pool    |
|---------------|------|--------------|-------|---------|
| gpt-5.6-sol   | 2    | 9            | 6     | chatgpt |
| gpt-5.6-terra | 2    | 7            | 5     | chatgpt |
| gpt-5.6-luna  | 2    | 7*           | 4     | chatgpt |
| sonnet-5      | 3    | 5            | 7     | claude  |
| opus-4.8      | 2    | 7            | 8     | claude  |
| fable-5       | 2    | 9            | 9     | claude  |
| opus-5        | 3    | 10           | 9     | claude  |
| glm-5.2       | 2    | 6            | 4     | glm     |

How to apply:
- These are defaults, not limits. Standing permission to override: if a model's output doesn't meet the bar, rerun or redo with a smarter one without asking. Judge the output, not the cost. Escalating a flat-pool model costs nothing but the cap.
- Cost is a tie-breaker only; when axes conflict for anything that ships: intelligence > taste > cost. Every pool is flat, so cost rarely decides: spend the better model, and spread load so no one pool's cap is the bottleneck.
- GPT / Codex availability is per-box: check the routing banner injected at session start (rendered live from `config.toml` + `config.local.toml`). On a box without codex, substitute glm (via opencode) wherever these lines say a gpt-5.6 tier.
- Sol is the best agentic/terminal coder. Hard/multi-file/agentic → sol; routine clear-spec/migrations → terra (spares Sol's cap); trivial edits/data-munging → glm-5.2 (#2 on LMArena Code, 1M ctx).
- `7*` for luna means the score is a dial, not a fact: it is the one model here whose reasoning effort spans its whole range, from AA-index ~33 at effort `none` to ~51 at high, which is level with glm-5.2 Max and above opus-5 on low. Codex defaults it to `none`, so an unqualified `codex exec -c model=gpt-5.6-luna` gets you the 33, not the 51. ALWAYS pass the effort you meant: `-c model_reasoning_effort="high"` for anything real, and leave it at `none` only for closed-question checks and triage (the verify lane's stand-in while the local model is down). Cheapest cost-per-task on the box at any effort, so it is the volume lane whenever taste is not in play.
- Anything user-facing (UI, copy, API design) needs taste ≥ 7 → opus/fable, never a GPT tier.
- Reviews of plans/implementations: opus-5 default (it leads Fable on agentic-coding and knowledge-work benchmarks and shares its pool), add sol (or glm) as an independent cross-family perspective when stakes are high. Spend cross-family diversity, all flat.
- fable-5 keeps one job: multi-hour autonomous runs and the architect lane, where its longer-horizon behaviour still shows. Everywhere else opus-5 supersedes it.
- Never use Haiku.
- Effort discipline: run Fable on **high** by default. xhigh is token-hungry; max/extra is a furnace with worse outputs than lower options. Reach past high only when a hard problem genuinely stalls.
- Mechanics: glm runs headless via opencode (`opencode run --model glm/glm-5.2`). CAUTION: without `--auto` it hangs forever waiting for tool approval in non-interactive mode. For read-only reviews, inline the file contents into the prompt so it needs no tools; for builds, `--auto` may be blocked by the harness classifier unless the user explicitly authorized it.
- Claude models run via the Agent/Workflow model parameter: opus-5 is `model: 'opus'`, plus `'fable'` and `'sonnet'`.

Using glm inside workflows and subagents (the model parameter only takes Claude models, so use a wrapper): spawn a thin Claude wrapper agent with `model: 'sonnet', effort: 'low'` whose prompt instructs it to write a self-contained prompt, run `opencode run` via Bash, and return the result verbatim.

Architect/builder loop (for well-spec'd multi-lane work): Fable architects, meaning it specs a one-PR slice, splits it into 1 to 4 lanes checked for file-set overlap, and commits acceptance gates. glm builds each lane under a fresh `opencode run` in its own git worktree. The repo is the memory (specs, gates, handoffs live in files, not chat). Frozen gates replace trust: validate both test passage and diff alignment before merging.

## Model routing

Routing is **per-box**: base rules live in `config.toml` `[routing]`/`[engines]`; each
machine overrides what differs (codex access, active engines) in gitignored
`config.local.toml` (start from `configs/config.local.example.toml`). `setup.sh` renders
the merged view into gitignored `routing.local.md`, imported next line, so this stays
current per machine without ever touching committed files.

@routing.local.md

## Generated agent context

Cross-app behavior and enabled-tool preferences are rendered from the merged
configuration just like routing. This keeps machine-specific guidance out of the
committed global instructions.

@agent-integrations.local.md

## The toolbelt

Each tool below is loaded here and toggled in `config.toml`. Delete a line to unload.

<!-- claude-only -->
@tools/RTK.md
<!-- /claude-only -->
@tools/mint.md
@tools/blueprint.md
