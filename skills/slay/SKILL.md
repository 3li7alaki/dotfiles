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
an explicit ID.

## Who files the task

The human does not file tickets. When `$SLAYZONE_TASK_ID` is absent but the repo's
AGENTS.md carries a `# SlayZone Environment` block, this repo is onboarded and you are
the orchestrator: file the task yourself for work that will edit files and outlive a
single exchange.

```bash
slay tasks create "<short imperative title>" --project <name> --status in_progress
```

Create it directly in `in_progress` because that is the status the onboarding automations
watch. Do not open a task for a question answerable by reading, a one-line fix, or
anything read-only. With no task id and no block, do not touch SlayZone at all and do not
infer a project from the current directory.

## Onboarding a repository

Run the script, never the steps by hand:

```bash
bash "$DOTFILES/scripts/slay-onboard.sh" [repo-path] [project-name]
```

It is idempotent: it creates or re-points the Slay project, installs the built-in slay
skills, appends the `slay init instructions` block to the repo's AGENTS.md and CLAUDE.md,
pins T3's `defaultThreadEnvMode` to `local`, and registers two automations on
`in_progress`. `t3-project` registers the task worktree with T3; `herdr-workspace` opens
that same path as a herdr workspace, and is skipped when herdr is absent. Those last
three are the point: without them you review the main checkout while the agent works in
the task worktree.

## Surfaces

Slay owns board state, worktree lifecycle, and shipping. T3 owns conversation, diff
review, and phone access; herdr owns panes and agent state at the desk. Both are harness
UIs only: the underlying Codex or Claude process performs the `slay` operations. Never cut
a second checkout of a tree Slay already isolated, not with `git worktree`, not with
herdr's new-worktree action, and not through T3.
