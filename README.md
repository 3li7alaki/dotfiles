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
| [t3code](https://github.com/pingdotgg/t3code) | Desktop app + CLI | darwin, linux | on | Primary multi-harness agent chat and diff-review surface |

### Command-line tools

| Add-on | Class | Platform | Default | Purpose |
| --- | --- | --- | --- | --- |
| [stow](https://www.gnu.org/software/stow/) | CLI | Linux / macOS | on | Symlink-farm manager used by setup for complete, repo-owned configuration files |
| [tmux](https://github.com/tmux/tmux) | CLI | Linux / macOS | on | Persistent terminal multiplexer for durable sessions, panes, and remote work |
| [pass](https://www.passwordstore.org/) | CLI | Linux / macOS | on | GPG-encrypted local secret store with a no-plaintext-file environment launcher |
| [github-cli](https://github.com/cli/cli) | CLI | Linux / macOS | on | Official GitHub CLI for pull requests, checks, issues, releases, and API access |
| [jq](https://github.com/jqlang/jq) | CLI | Linux / macOS | on | Lightweight structural JSON querying, validation, filtering, and transformation |
| [fzf](https://github.com/junegunn/fzf) | CLI | Linux / macOS | on | Interactive fuzzy finder with shell history, path selection, and completion bindings |
| [fd](https://github.com/sharkdp/fd) | CLI | Linux / macOS | on | Fast, user-friendly path search with Git-aware filtering and concise syntax |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | CLI | Linux / macOS | on | Fast recursive code search with Git-aware filtering and useful defaults |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | CLI | Linux / macOS | on | Smarter cd — jump to frequently used directories with z/zi |
| [direnv](https://direnv.net/) | CLI | Linux / macOS | on | Per-directory env autoload from .envrc (needs `direnv allow` per repo) |
| [model](https://github.com/ggml-org/llama.cpp) | CLI | darwin | on | Local model control — daemon on/off + GGUF registry (list/use/pull) |
| [aria2](https://aria2.github.io/) | CLI | Linux / macOS | on | Multi-connection downloader — fast HF model pulls (curl single-stream throttles) |
| [rtk](https://github.com/rtk-ai/rtk) | CLI | Linux / macOS | on | Rust Token Killer — token-optimizing CLI proxy |
| [mint](https://github.com/3li7alaki/mint) | CLI | Linux / macOS | on | Atomic completion ledger with snapshot-bound receipts |
| [codex](https://github.com/openai/codex) | CLI | Linux / macOS | on | OpenAI Codex CLI — GPT-5.6 worker |
| [opencode](https://github.com/anomalyco/opencode) | CLI | Linux / macOS | on | OpenCode — headless agent runner; hosts GLM + the local model via opencode.json |
| [llama-server](https://github.com/ggml-org/llama.cpp) | CLI | darwin | on | llama.cpp server — local OpenAI endpoint; wins on ops, MTP, and M5 tensor-API prefill |

### Stow-managed configurations

| Package | Target | Requires | Default | Purpose |
| --- | --- | --- | --- | --- |
| [tmux](https://github.com/tmux/tmux) | HOME | stow, tmux | on | Portable tmux defaults and a macOS/Linux clipboard bridge |
| [raycast](https://raycast.com) | HOME | stow | on | Raycast custom AI provider — points Raycast at the local llama-server (:8080) |

### Skills and MCP integrations

| Add-on | Class | Default | Purpose |
| --- | --- | --- | --- |
| [ponytail](https://github.com/DietrichGebert/ponytail) | Claude plugin | on | Lazy-senior-dev discipline — the laziest solution that works |
| [caveman](https://github.com/JuliusBrussee/caveman) | Claude plugin | on | Terse caveman-speak — ~65% fewer output tokens, code/commands byte-exact |
| [codebase-memory](https://github.com/DeusData/codebase-memory-mcp) | MCP server | on | Auto-indexed code knowledge graph — structural queries over the codebase |
| [impeccable](https://github.com/pbakaus/impeccable) | Skill bundle | on | Frontend design + UX review — anti-slop design language (impeccable.style) |
| [pinchtab](https://github.com/pinchtab/pinchtab) | Repo skill | on | Browser automation via PinchTab |
| [slay](https://github.com/debuglebowski/slayzone) | Shared agent skill | on | Runtime-discovered Slay CLI guidance shared by Claude and Codex |
| [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Claude plugin | on | Design intelligence — styles, palettes, font pairings, UX guidelines |
| skillless | Skill bundle | on | Skill finder — discovers/installs relevant skills on demand (/discover, /plans) |

### Cross-app integrations

| Integration | Requires | Default | Ownership |
| --- | --- | --- | --- |
| slayzone-t3-workflow | slayzone, t3code | on | SlayZone owns task/worktree/shipping; T3 is the primary chat in that existing workspace |

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
| local-model | User daemon (darwin) | on | Local model endpoint (llama.cpp) — idle-unloads so it costs no RAM at rest |
| revise-claude-md | Scheduled task | on | Weekly CLAUDE.md hygiene across ~/Projects repos |
| update-tools | Scheduled task | on | Weekly tool auto-update (latest binaries) |

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
`routing.local.md`. `CLAUDE.md` imports the rendered file, and the routing hook refreshes
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
| `skills/` | Skills owned by this repo and symlinked into an agent |
| `tools/` | Version-controlled instruction pages imported by `CLAUDE.md` |
| `scripts/` | Maintenance and consistency helpers |
| `agent-integrations.local.md` | Gitignored, generated cross-app instructions for this machine |

## Agent workspace workflow

The operating model deliberately gives each layer one job:

| Layer | Owner | Responsibility |
| --- | --- | --- |
| Machine baseline | dotfiles | Apps, CLIs, global skills/MCPs, hooks, routing, verification |
| Portfolio and isolation | SlayZone | Kanban, task state, task worktrees, terminals, browser, Library trials |
| Agent conversation | T3 Code | Primary chat, harness/model selection, and diff review |

For a Slay-owned task, open its existing task worktree in T3 Code and start a normal
thread there. Do not ask T3 to create another worktree for that thread. T3 supports an
existing project working directory as the session cwd; its optional worktree action is
for work not already isolated by SlayZone. Launching `t3` from the Slay task terminal
also carries `SLAYZONE_TASK_ID` and `SLAYZONE_PROJECT_ID` into the process, allowing the
agent to use `slay` to read or update its Kanban task. T3 itself needs no Slay plugin:
the Codex or Claude process underneath it reads the generated global instructions and
the shared `slay` skill.

`setup.sh` renders `agent-integrations.local.md` from the merged configuration. Claude
imports that file through the dotfiles hub; Codex receives the same text in a
marker-owned block in `~/.codex/AGENTS.md`. The block is removed automatically when the
last integration/tool preference is disabled. The global `slay` skill is linked for
both agents and consults the installed CLI help at runtime, avoiding a copied command
catalog that would go stale.

Use SlayZone's Library to discover and trial skills or MCPs, with project-scoped links
for experiments. When an add-on becomes dependable, promote its source, install command,
configuration, and verification into `config.toml`. This keeps experimentation fast
without making SlayZone's local SQLite database the only record of the setup.

Avoid dual ownership: global agent instructions, hooks, MCP registrations, binaries,
and routing remain dotfiles-owned. SlayZone owns task state, worktrees, and shipping;
T3 consumes the worktree as the chat and review surface.

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
