---
name: mint
description: Use when recording why an atomic unit of work is allowed to be called done — a claim with a goal, explicit scope, observable acceptance criteria, and declared gates/reviews. mint is a CLI on PATH, driven via Bash, not a captive skill.
---

# mint — atomic completion ledger

`mint` is a binary on PATH, **not** a skill or plugin. This dispatcher exists only so
`Skill(mint)` resolves to real guidance instead of erroring. Never try to run mint as a
skill — drive the CLI via Bash.

Before acting, inspect the installed version's help. Never guess a command or flag from
memory — the surface evolves and this skill deliberately does not duplicate it:

```bash
mint --help
mint <command> --help
```

The stable flow:

```text
mint spec  →  mint exec init  →  mint verify + independent reviews  →  mint done  →  mint receipt verify
```

Only the receipt from `mint done` is proof of completion. mint owns the completion floor,
attempt evidence, exact source snapshots, immutable receipts, and receipt freshness. The
driver (you) owns tickets, worktrees, terminals, agents, retries, Git/PR ops, and shipping.

State is global, repository-keyed, worktree-isolated under XDG state (or `MINT_STATE_HOME`).
mint creates no repository `.mint` directory and never edits `.gitignore`.

The full contract lives in mint's `AGENTS.md` at https://github.com/3li7alaki/mint — that,
plus `mint <command> --help`, is authoritative over anything remembered here.
