---
name: slay
description: Use when running inside a SlayZone task, when asked to inspect or update its board, task, worktree, browser, processes, or shipping state, or when onboarding a repository into SlayZone and T3 Code.
---

# SlayZone CLI

Use the installed `slay` CLI to interact with SlayZone. This skill deliberately does
not duplicate its evolving command reference.

Before acting, inspect the installed version's help:

```bash
slay --help
slay tasks --help
```

Inspect the relevant domain's help before using flags you have not already verified.
Never guess a command or flag from memory.

Inside a SlayZone task terminal, `$SLAYZONE_TASK_ID` identifies the current task and
`$SLAYZONE_PROJECT_ID` identifies its project. Most task operations can therefore omit
an explicit ID. If neither variable exists, do not assume the current directory belongs
to a Slay task; ask for or discover the intended task explicitly.

## Onboarding a repository

Run the script, never the steps by hand:

```bash
bash "$DOTFILES/scripts/slay-onboard.sh" [repo-path] [project-name]
```

It is idempotent and does five things: creates or re-points the Slay project, installs the
built-in slay skills, appends the `slay init instructions` block to the repo's AGENTS.md and
CLAUDE.md, creates the `t3-project` automation that registers each task's worktree with T3 on
`in_progress`, and pins T3's `defaultThreadEnvMode` to `local`. The last two are the point:
without them you review the main checkout in T3 while the agent works in the task worktree.

## Chat surface

When T3 Code is the chat surface, it remains only the harness UI. The underlying Codex
or Claude process performs `slay` operations. Keep the existing Slay worktree: do not
create a second T3 worktree for the same task. Slay owns board state, worktree lifecycle,
and shipping; T3 owns conversation and diff review.
