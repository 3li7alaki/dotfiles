# CLI distribution

How the tools in the lab get onto someone's machine. Rules and pointers only.
The previous version of this document carried a full `install.sh`, two workflow
files and a landing-page spec, and every one of them had drifted from the code it
was copied from. Anything expressible as a working file lives in the file.

## Canonical implementations

Copy these. Do not write a new one.

| thing | canonical source |
|---|---|
| `install.sh` | `mint/install.sh`, 92 lines |
| CI | `mint/.github/workflows/ci.yml` |
| Release | `mint/.github/workflows/release.yml` |
| README shape | `mint/README.md` |
| Landing page | the `area-51` repo, whose README documents adding a tool |

blueprint's installer is mint's with the names changed. That is the point: if a
third one needs to differ, the difference is the thing to justify.

## Rules

These are not derivable from reading the code, which is why they are written down.

- **GitHub Releases hosts the binaries.** Not a domain, not a VPS. Free,
  CDN-backed, versioned, and a container restart cannot break an install.
- **Rolling `latest`.** Every push to main rebuilds and republishes one `latest`
  release. No version tags, no semver, and `install.sh` always fetches `latest`.
- **`install.sh` is the updater.** Running it twice is safe and acts as an
  upgrade, so a duplicate PATH guard is mandatory.
- **`${XDG_DATA_HOME:-$HOME/.local/share}/<tool>`** for the install, symlinked
  into `~/.local/bin`. Never `~/.<tool>`.
- **No root, no runtime dependencies.** A user installing a flashcard tool should
  not end up with a language toolchain they did not ask for.
- **Flags:** `--version`, `--no-path`, `--uninstall`. All three, every tool.
- **A tool never graduates to its own domain.** Everything lives under
  `area-51.cloud`. `owl-post.dev` was tried and dropped, and it cost a migration
  because releases and a live API had been built on top of it.

## Claude Code plugins

Non-obvious, and worth keeping:

- `npx skills add` only handles `SKILL.md`. Hooks, `plugin.json` and agents need
  wiring separately.
- `marketplace.json` goes in `.claude-plugin/` for marketplace discovery.
- A plugin does not need the binary's install path. `claude plugin marketplace add`
  is independent, which is why a compiled tool can still ship one.

## Outstanding

Audited 2026-07-26.

| tool | `--version` | `--no-path` | `--uninstall` | ships a binary | lines |
|---|---|---|---|---|---|
| mint | yes | yes | yes | yes | 92 |
| blueprint | yes | yes | yes | yes | 92 |
| flash | yes | no | no | **no, git clone** | 179 |
| owl post | no | no | no | yes | 95 |

### flash

No artifact at all. `install.sh` clones the repo, installs Bun if missing, runs
`bun install`, then symlinks `src/cli.ts` into `~/.local/bin`, so every invocation
is Bun parsing TypeScript and `git reset --hard origin/main` gives users whatever
landed minutes ago. Zero published releases. Do these in order:

- [ ] Add `ci.yml`. 331 tests, a linter and a typechecker exist and none run on
      push. Smallest win, independent of everything below.
- [ ] Embed `templates/` at build time. **Blocker for compiling:**
      `src/commands/templates.ts:16` resolves `join(import.meta.dir, "../../templates")`
      and reads the directory, which does not exist in a compiled binary and fails
      silently rather than loudly.
- [ ] Add `release.yml` with a `bun build --compile` matrix.
- [ ] Only then rewrite `install.sh` from mint's. Verify the compiled binary runs
      first: this is the step that breaks installs for everyone if it is wrong.
- [ ] Keep the existing plugin block, it already uses the marketplace.
- [ ] Then update `runtime` in `area-51/src/content/tools/flash.yaml`.

### owl post

- [ ] **Blocked: 74 uncommitted modified files.** Clear that tree first.
- [ ] Delete `apps/web`. area-51 serves the page. Keep the API and relay, which
      become their own Dokploy app, and the registry, which becomes another.
- [ ] Move `scripts/install.sh` to the repo root. area-51 derives the installer
      redirect from the tool name, so that path is the one thing breaking it.
- [ ] Repoint releases off `owl-post.dev` to GitHub Releases. Also fixes
      `apps/cli/src/commands/update.ts`, which reads
      `owl-post.dev/releases/latest.json` and so breaks `owl update` for people
      who already installed, not only new ones.
- [ ] Add the three missing flags. Re-enable `.github/workflows-disabled/`.
- [ ] Replace `security@owl-post.dev`. GitHub private vulnerability reporting
      needs no email hosting.
- [ ] Untrack `node-compile-cache/`: 463 files, 2.3MB, keyed to one Node version
      and one uid. Gitignore it.
- [ ] Two tracked lockfiles while `CLAUDE.md` declares pnpm plus Turborepo.

### mint and blueprint

Compliant. Governance only: neither has `SECURITY.md`, and blueprint has no
`CONTRIBUTING.md`.
