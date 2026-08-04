# dotfiles

A declarative, cross-machine setup for desktop agent apps, command-line tools, static
configuration packages, skills, MCP servers, Claude Code wiring, local model runtimes,
and model routing. `config.toml` is the source of truth; `setup.sh` makes the machine
match it.

## Quick start

Fresh machine:

```bash
curl -fsSL https://raw.githubusercontent.com/3li7alaki/dotfiles/main/bootstrap.sh | bash
```

Existing clone:

```bash
./setup.sh
```

Useful safe checks:

```bash
./setup.sh --dry-run   # preview changes
./setup.sh --verify    # check enabled components without installing
```

The setup is idempotent and keeps ownership narrow: complete repo-owned files use GNU
Stow, JSON keys are merged, hooks and cron entries use markers, shell integrations use
marker-owned rc blocks, and existing personal config outside those owned regions is
preserved.

## Add-on catalog

This catalog is generated from `config.toml`; do not edit its tables by hand. After
adding or changing an add-on, run `scripts/render-readme-catalog.py`. CI/local checks can
use `scripts/render-readme-catalog.py --check` to catch drift.

<!-- catalog:start -->

### Desktop apps

| Add-on | Class | Platform | Default | Purpose |
| --- | --- | --- | --- | --- |
| [slayzone](https://github.com/debuglebowski/slayzone) | Desktop app + CLI | darwin, linux | on | Local-first task board, worktree/terminal workspace, and agent-config library |
| [t3code](https://github.com/pingdotgg/t3code) | Desktop app + CLI | darwin, linux | on | Multi-harness agent chat, diff review, and the only phone-reachable surface |

### Command-line tools

| Add-on | Class | Platform | Default | Purpose |
| --- | --- | --- | --- | --- |
| [stow](https://www.gnu.org/software/stow/) | CLI | Linux / macOS | on | Symlink-farm manager used by setup for complete, repo-owned configuration files |
| [tmux](https://github.com/tmux/tmux) | CLI | Linux / macOS | on | Persistent terminal multiplexer for durable sessions, panes, and remote work |
| [herdr](https://github.com/herdrdev/herdr) | CLI | Linux / macOS | on | Agent-aware multiplexer: tmux's model plus per-pane agent state and a socket API |
| [pass](https://www.passwordstore.org/) | CLI | Linux / macOS | on | GPG-encrypted local secret store with a no-plaintext-file environment launcher |
| [github-cli](https://github.com/cli/cli) | CLI | Linux / macOS | on | Official GitHub CLI for pull requests, checks, issues, releases, and API access |
| [dokploy](https://github.com/Dokploy/cli) | CLI | Linux / macOS | on | Dokploy panel CLI (449 OpenAPI-generated commands) plus `dok`, its per-VPS profile front end |
| [jq](https://github.com/jqlang/jq) | CLI | Linux / macOS | on | Lightweight structural JSON querying, validation, filtering, and transformation |
| [fribidi](https://github.com/fribidi/fribidi) | CLI | Linux / macOS | on | Arabic/Hebrew in a terminal with no bidi engine: `bidi` reorders and shapes RTL text |
| [zsh-completion](https://zsh.sourceforge.io/Doc/Release/Completion-System.html) | CLI | Linux / macOS | on | zsh completion system (compinit) with cached dump, case-insensitive and mid-word matching |
| [fzf](https://github.com/junegunn/fzf) | CLI | Linux / macOS | on | Interactive fuzzy finder with shell history, path selection, and completion bindings |
| [fzf-tab](https://github.com/Aloxaf/fzf-tab) | CLI | darwin | on | Every zsh TAB becomes an fzf picker: paths, git refs, flags, processes, zoxide jumps |
| [fd](https://github.com/sharkdp/fd) | CLI | Linux / macOS | on | Fast, user-friendly path search with Git-aware filtering and concise syntax |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | CLI | Linux / macOS | on | Fast recursive code search with Git-aware filtering and useful defaults |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | CLI | Linux / macOS | on | Smarter cd — jump to frequently used directories with z/zi |
| [direnv](https://direnv.net/) | CLI | Linux / macOS | on | Per-directory env autoload from .envrc (needs `direnv allow` per repo) |
| [model](https://github.com/ggml-org/llama.cpp) | CLI | darwin | on | Local model control — daemon on/off + GGUF registry (list/use/pull) |
| [aria2](https://aria2.github.io/) | CLI | Linux / macOS | on | Multi-connection downloader — fast HF model pulls (curl single-stream throttles) |
| [rtk](https://github.com/rtk-ai/rtk) | CLI | Linux / macOS | on | Rust Token Killer — token-optimizing CLI proxy |
| [mint](https://github.com/3li7alaki/mint) | CLI | Linux / macOS | on | Atomic completion ledger with snapshot-bound receipts |
| [blueprint](https://github.com/3li7alaki/blueprint) | CLI | Linux / macOS | on | Spec layer above the code: grills the idea, then gates code against the answers |
| latest-version | CLI | Linux / macOS | on | Registry truth for 'what version is current': what [hooks.version-freshness] gates on |
| [codex](https://github.com/openai/codex) | CLI | Linux / macOS | on | OpenAI Codex CLI — GPT-5.6 worker |
| [codex-security](https://github.com/openai/codex-security) | CLI | Linux / macOS | on | OpenAI Codex Security: AppSec scan of a diff, with false-positive memory across runs |
| [opencode](https://github.com/anomalyco/opencode) | CLI | Linux / macOS | on | OpenCode — headless agent runner; hosts GLM + the local model via opencode.json |
| [llama-server](https://github.com/ggml-org/llama.cpp) | CLI | darwin | on | llama.cpp server — local OpenAI endpoint; wins on ops, MTP, and M5 tensor-API prefill |

### Stow-managed configurations

| Package | Target | Requires | Default | Purpose |
| --- | --- | --- | --- | --- |
| [tmux](https://github.com/tmux/tmux) | HOME | stow, tmux | on | Portable tmux defaults and a macOS/Linux clipboard bridge |
| [raycast](https://raycast.com) | HOME | stow | on | Raycast custom AI provider — points Raycast at the local llama-server (:18080) |

### Skills and MCP integrations

| Add-on | Class | Default | Purpose |
| --- | --- | --- | --- |
| [ponytail](https://github.com/DietrichGebert/ponytail) | Claude plugin | on | Lazy-senior-dev discipline — the laziest solution that works |
| [caveman](https://github.com/JuliusBrussee/caveman) | Claude plugin | on | Terse caveman-speak — ~65% fewer output tokens, code/commands byte-exact |
| [codebase-memory](https://github.com/DeusData/codebase-memory-mcp) | MCP server | on | Auto-indexed code knowledge graph — structural queries over the codebase |
| [impeccable](https://github.com/pbakaus/impeccable) | Skill bundle | on | Frontend design + UX review — anti-slop design language (impeccable.style) |
| [pinchtab](https://github.com/pinchtab/pinchtab) | Repo skill | on | Browser automation via PinchTab |
| [slay](https://github.com/debuglebowski/slayzone) | Shared agent skill | on | Runtime-discovered Slay CLI guidance shared by Claude and Codex |
| [mint](https://github.com/3li7alaki/mint) | Shared agent skill | on | Dispatcher so Skill(mint) resolves to CLI guidance instead of erroring |
| handoff | Shared agent skill | on | Continuation prompt for a fresh session — file + clipboard, refs not copies |
| [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Claude plugin | on | Design intelligence — styles, palettes, font pairings, UX guidelines |
| skillless | Skill bundle | on | Skill finder — discovers/installs relevant skills on demand (/discover, /plans) |

### Cross-app integrations

| Integration | Requires | Default | Ownership |
| --- | --- | --- | --- |
| slayzone-t3-workflow | slayzone, t3code | on | The agent files the Slay task; SlayZone cuts the worktree; T3 and herdr consume it |

### Official Claude plugins

| Add-on | Class | Default | Purpose |
| --- | --- | --- | --- |
| [commit-commands](https://github.com/anthropics/claude-plugins-official) | Claude plugin | on | Commit, push, and pull-request workflows |
| [context7](https://github.com/anthropics/claude-plugins-official) | Claude plugin | on | Current library documentation lookup |
| [gopls-lsp](https://github.com/anthropics/claude-plugins-official) | Claude plugin | on | Go language-server integration |
| [typescript-lsp](https://github.com/anthropics/claude-plugins-official) | Claude plugin | on | TypeScript language-server integration |
| [php-lsp](https://github.com/anthropics/claude-plugins-official) | Claude plugin | on | PHP language-server integration |
| [pyright-lsp](https://github.com/anthropics/claude-plugins-official) | Claude plugin | on | Python language-server integration |
| [claude-md-management](https://github.com/anthropics/claude-plugins-official) | Claude plugin | on | CLAUDE.md maintenance workflows |

### Automation and wiring

| Component | Class | Default | Purpose |
| --- | --- | --- | --- |
| rtk | Claude hook | on | rtk Bash rewrite hook — transparent token-optimized command proxy |
| routing | Claude hook | on | Injects model routing — dispatch bulk→codex, mechanical→glm, etc. |
| cbm-gate | Claude hook | on | Nudges code discovery toward the codebase graph — blocks once per session, then allows |
| secret-scan | Claude hook | on | Pre-commit secret scan — gitleaks blocks, the local model warns on the long tail |
| version-freshness | Claude hook | on | Blocks a manifest write or pinned install that is a breaking version behind the registry |
| handoff-checkpoint | Claude hook | on | Suggests a handoff at a seam once conversation growth crosses the band |
| local-model | User daemon (darwin) | on | Local model endpoint (llama.cpp) — idle-unloads so it costs no RAM at rest |
| revise-claude-md | Scheduled task | on | Weekly CLAUDE.md hygiene across ~/Projects repos |
| update-tools | Scheduled task | on | Weekly tool auto-update (latest binaries) |
| distill-memory | Scheduled task | on | Weekly memory distillation: promotes repeated guidance into candidate memories |

<!-- catalog:end -->

## Turning things on and off

Managed entries use an `enabled` or `active` switch in `config.toml`; official plugins
are enabled by membership in `plugins.enabled`. Change the value/list and re-run
`./setup.sh`. Machine-specific differences belong in the gitignored `config.local.toml`,
which deep-merges over the committed defaults:

```toml
[tools.zoxide]
enabled = false

[engines.local]
active = true
```

Disabling means deactivating cleanly, not destroying user data. For example, disabling
zoxide removes only the generated blocks from Bash/Zsh/Fish startup files; its binary
and directory history remain available for a later re-enable. MCP registrations,
Stow package links, skill symlinks, hooks, daemons, and cron entries are similarly
removed from their active wiring where supported.

An integration also checks its `requires_apps` list. For example, the SlayZone/T3
instructions render only when `[integrations.slayzone-t3-workflow]` and both required app entries are
enabled in the merged machine configuration.

Tools may declare `agent_guidance`, which is rendered only while that tool is enabled.
Ripgrep uses this to make Claude and Codex prefer `rg` for repository search and
`rg --files` for file discovery while preserving real `grep` for portable scripts and
compatible pipelines. It is guidance rather than a command-rewriting hook because the
two programs do not have identical flags or behavior.

`fd` follows the same pattern for path discovery: agents prefer it for ordinary
interactive filename/type/extension searches while retaining `find` for portable
scripts, complex predicates, and filesystem-specific behavior.

GitHub CLI guidance prefers structured `gh` output over browser scraping for PRs,
checks, issues, releases, and API data. Installation is dotfiles-owned, but credentials
remain user-owned: setup reports missing authentication without attempting login or
storing a token, and generated guidance keeps remote mutations request-scoped.

`jq` is the structural JSON lane for that output and other APIs/configuration: agents
prefer it over text matching, use compact/raw/exit-status modes deliberately, and retain
Python or a project language when the transformation becomes application logic.

`fzf` provides the interactive lane: fuzzy history with `Ctrl-r`, path insertion with
`Ctrl-t`, directory changes with `Alt-c`, and `**` completion where supported. Its shell
initializer uses `fd` for Git-aware path candidates, falls back to ripgrep, and supports
both modern embedded fzf integrations and older distro-packaged scripts. Generated agent
guidance keeps automation deterministic—agents use fzf only when an actual human picker
is intended.

## Static configurations with Stow

`setup.sh` is still the only entry point. It installs GNU Stow, then reconciles enabled
entries under `[stow]`; users do not need a second manual setup workflow. Each package
under `stow/` mirrors paths below its declared target, normally `HOME`:

```text
stow/tmux/.tmux.conf             -> ~/.tmux.conf
stow/tmux/.local/bin/tmux-copy   -> ~/.local/bin/tmux-copy
```

Stow is reserved for complete files owned by this repository. Generated files,
marker-managed sections, secrets, and machine-local state remain under `setup.sh` or
`config.local.toml`. Setup uses leaf links instead of folding whole directories, allowing
future packages to safely share locations such as `~/.config`.

An existing unmanaged destination is a conflict: Stow stops and reports it instead of
overwriting the file. Review and migrate that file deliberately, then rerun setup. The
automation never uses `stow --adopt`, because that could replace committed package
contents with an arbitrary machine's local file. `./setup.sh --dry-run` shows the Stow
operation without changing links, and disabling `[stow.tmux]` unlinks only files owned
by that package.

The initial tmux package keeps the standard `Ctrl-b` prefix, enables mouse and vi copy
mode, preserves pane working directories, and provides macOS/Linux clipboard support.
Useful bindings include `prefix + r` to reload, `prefix + |`/`-` to split, and
`prefix + h/j/k/l` to move between panes. It deliberately has no plugin manager or theme
dependency, keeping fresh-machine and remote sessions reliable.

## Local development secrets

`pass` stores each secret as a GPG-encrypted file. Dotfiles installs the program and its
GnuPG dependency but never creates, imports, or exports keys; initializes a password
store; clones a secret repository; or decrypts an entry during setup.

For local development commands, `pass-env` keeps decrypted values out of `.env` files,
shell history, command arguments, and normal output:

```text
GPG-encrypted pass entry
          |
          v
pass-env process memory --> child-process environment
          X
   no plaintext file/output/prompt
```

Create a private reference map outside the repository, for example
`~/.config/pass-env/my-project.map`, with mode `0600`:

```text
DATABASE_URL=dev/my-project/database-url
THIRD_PARTY_TOKEN=dev/my-project/third-party-token
```

Then launch only the process that needs those values:

```bash
pass-env --map ~/.config/pass-env/my-project.map -- npm run dev
```

For human-driven lookup, `pass-fzf` fuzzy-selects entry names without decrypting them in
the picker or adding a secret preview. Its default output is only the selected name, so
it composes with other commands; the safer everyday action copies the first line without
printing it:

```bash
pass-fzf --clip
```

On Linux this delegates to `pass --clip`, which restores the prior clipboard after its
configured timeout. The macOS path provides equivalent `pbcopy`/`pbpaste` behavior.
Use `pass-env` instead when a development process needs one or more environment variables.

Each mapping resolves the first line of its `pass` entry directly into the named
environment variable. This prevents accidental plaintext persistence and transcript
exposure; it is not a sandbox. The child process can read every variable it receives,
so maps should contain only the least privilege needed for that command and should not
be used to hand production credentials to an agent-controlled process.

Start a local override from [`configs/config.local.example.toml`](configs/config.local.example.toml).
Whole entries can be added there when an add-on exists on only one machine.

## How model routing works

Routing is guidance injected into the coding agent, not a background scheduler. The
agent classifies the task, reads the corresponding lane from `[routing]`, and invokes
the command declared for that model in `[engines]`.

```text
task shape
  ├─ routine implementation ──> bulk       ──> gpt-5.6-terra
  ├─ hard / multi-file work  ──> heavy      ──> gpt-5.6-sol
  ├─ mechanical edits        ──> mechanical ──> GLM via OpenCode
  ├─ UI / user-facing work   ──> ui         ──> opus-4.8
  ├─ review                  ──> review     ──> fable-5
  └─ private / verification  ──> private    ──> local OpenAI-compatible endpoint
```

The base rules in `config.toml` merge with `config.local.toml`, then
`hooks/routing-activate.sh` renders that machine’s effective view to the gitignored
`routing.local.md`. `AGENTS.md` imports the rendered file, and the routing hook refreshes
the same information in active sessions.

If a cloud engine is unavailable or rate-limited, the agent walks `[routing].fallback`
in order. The local engine is deliberately excluded from that fallback: it receives
small private or asynchronous verification jobs, not abandoned agentic work. Engines
with `active = false`, a missing required environment variable, or a dead required
endpoint should not be selected.

## Repository layout

| Path | Ownership |
| --- | --- |
| `config.toml` | Committed defaults and the complete component registry |
| `config.local.toml` | Gitignored per-machine overrides |
| `setup.sh` | Reconciles the machine with the merged configuration |
| `bootstrap.sh` | Installs Git if needed, clones/updates the repo, then runs setup |
| `configs/` | Templates copied or rendered into user config locations |
| `stow/` | Complete static configurations linked into their declared target |
| `hooks/` | Marker-managed Claude hooks and routing renderer |
| `AGENTS.md` | The global instruction hub, under the filename every harness reads |
| `CLAUDE.md` | A one-line pointer at `AGENTS.md`, kept only because Claude looks for it |
| `skills/` | Skills owned by this repo and symlinked into an agent |
| `tools/` | Version-controlled instruction pages imported by `AGENTS.md` |
| `scripts/` | Maintenance and consistency helpers |
| `agent-integrations.local.md` | Gitignored, generated cross-app instructions for this machine |
| `agents-global.local.md` | Gitignored, the flattened hub that Codex and opencode receive |

## Agent workspace workflow

The operating model deliberately gives each layer one job:

| Layer | Owner | Responsibility |
| --- | --- | --- |
| Machine baseline | dotfiles | Apps, CLIs, global skills/MCPs, hooks, routing, verification |
| Portfolio and isolation | SlayZone | Kanban, task state, task worktrees, terminals, browser, Library trials |
| Agent conversation | T3 Code | Chat, harness/model selection, diff review, and the phone |
| Terminal surface | herdr | Panes, per-pane agent state, and durable local sessions |

The board is never filed by hand. You chat in T3 or in a herdr pane, and the agent
decides whether the request deserves a task. `scripts/slay-onboard.sh` is what makes that
possible per repo: it creates the Slay project, installs the built-in slay skills, writes
a marker-guarded `# SlayZone Environment` block into the repo's `AGENTS.md`, and registers
two automations on `task_status_change -> in_progress`.

That marker is the signal the generated instructions key on. An agent with no
`$SLAYZONE_TASK_ID` that finds the block knows it is at the orchestrator's desk and files
the task itself, directly at the status the automations watch:

```bash
slay tasks create "<title>" --project <name> --status in_progress
```

SlayZone then cuts one worktree and both automations hand that same path onward, to T3 as
a project and to herdr as a workspace. One tree, two views, no tool cutting a second
checkout of a repo SlayZone already isolated. An agent that does have `$SLAYZONE_TASK_ID`
is already inside that tree and files nothing.

Both automation commands are stored as absolute paths resolved at onboard time. The
SlayZone app dispatches them with launchd's default `PATH`, which contains neither
`~/.local/bin` nor `/opt/homebrew/bin`, so a bare `t3` or `herdr` would resolve to
nothing. The herdr half is skipped entirely when herdr is not installed, and needs a
running herdr server when it is; with no server there is no desk to open a pane on, and
T3 still receives the worktree.

Start the herdr server by running `herdr`, never from a launch agent. On macOS a server
started in a `Background` launchd context passes that context to every pane, which breaks
keychain-backed CLIs and, in some reports, DNS inside panes. Upstream treats this as
expected macOS behavior rather than a bug to fix.

### One hub, every harness

`AGENTS.md` is the source of truth and `CLAUDE.md` is a one-line pointer at it, because
`AGENTS.md` is the filename Codex, opencode and the rest already read. Per repo that is all
it takes: each harness finds the file it looks for, natively.

The global layer is the part no harness handles, and the constraints are measured, not
assumed:

- Only Claude expands `@` imports into context. Codex reads the line and shells out to the
  file only when it happens to judge it relevant, so nothing load-bearing can sit behind an
  import. Before this wiring existed, Codex answered `ABSENT` when asked what its
  instructions forbid about dashes.
- Codex reads no `AGENTS.md` above a repository root, with or without a git repo, so
  `~/.codex/AGENTS.md` is its only global slot and that path is fixed.
- That fixed file has other owners. It currently holds a `codebase-memory-mcp` block and a
  caveman block alongside this one, which is why symlinking it at the hub is wrong: foreign
  installers would write into this git repo on every run.

So `scripts/render-global-context.py` flattens `AGENTS.md` and its imports into one
self-contained document and installs it as a marker-scoped block in each harness's global
file, leaving the other blocks untouched. Regions fenced with `<!-- claude-only -->` are
dropped from that copy and kept for Claude, which reads the sources directly; use it for
guidance that would be false elsewhere, like `tools/RTK.md` describing a Claude Code hook.

Accuracy is maintained by the routing hook, not by remembering to run setup. The routing
banner probes engine endpoints live, so it changes without any config edit; after printing,
the hook persists the same text to `routing.local.md` and re-syncs both harness blocks from
it. Around 20ms, and a no-op when nothing changed. `setup.sh --verify` additionally
diffs the rendered cache against `AGENTS.md`, so a stale copy is a reported failure rather
than something you discover through a model behaving oddly.

The global `slay` skill is linked for both agents through `~/.agents/skills/` and consults
the installed CLI help at runtime, avoiding a copied command catalog that would go stale.

Use SlayZone's Library to discover and trial skills or MCPs, with project-scoped links
for experiments. When an add-on becomes dependable, promote its source, install command,
configuration, and verification into `config.toml`. This keeps experimentation fast
without making SlayZone's local SQLite database the only record of the setup.

Avoid dual ownership: global agent instructions, hooks, MCP registrations, binaries,
and routing remain dotfiles-owned. SlayZone owns task state, worktrees, and shipping;
T3 and herdr consume that worktree as the chat surface and the terminal surface.

T3 is also the only surface that reaches the machine from a phone. Turn on Settings >
Connections > Network access and pair a device from the QR code behind `Create link`;
pairing exchanges a one-time bootstrap credential for a scoped token against your own
server, so it needs no T3 Connect account when both devices share a tailnet. The backend
lives in the desktop app, so the app has to be running for the phone to reach anything.

## Requirements and portability

The bootstrap supports common Linux package managers and Homebrew, including installing
Python through them when it is absent (notably on macOS). Setup requires Python 3.11+
for standard-library TOML parsing. Individual enabled components may also
need Git, curl, Node/npx, Claude Code, or crontab; `setup.sh` reports missing commands
before reconciliation. OS-specific entries declare `os = "darwin"` and are inert on
other systems rather than failing verification.

Secrets and host-specific paths do not belong in committed config. Keep API material in
the referenced local files/environment variables and use token paths such as `HOME/`,
`DOTFILES/`, `XDG_DATA/`, and `XDG_STATE/` inside config rather than absolute usernames.
