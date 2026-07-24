# mint — atomic completion ledger

> Drivers organize and execute work. mint records why an atomic unit is allowed to be called done.

mint is a CLI on PATH, not a skill or plugin. `Skill("mint")` resolves to a thin dispatcher
that just points back here — you never *run* mint as a skill; drive the CLI via Bash directly.
This document is the whole contract.

Use mint for an atomic claim with a goal, explicit scope, observable acceptance criteria, and
declared gates/reviews. The driver owns tickets, worktrees, terminals, agents, retries, Git/PR
operations, and shipping. mint owns the completion floor, attempt evidence, exact source
snapshots, immutable receipts, and receipt freshness.

State is global, repository-keyed, and worktree-isolated under XDG state (or
`MINT_STATE_HOME`). mint creates no repository `.mint` directory and never edits `.gitignore`.

Initialize each attempt with honest generic provenance: executor, vendor, model, locality, and
execution reference. mint does not own an executor registry, launch agents, or authenticate
typed identity. Independent reviews and the acceptance verdict are supplied by the driver;
safety-tier work requires a different vendor from the maker.

The stable flow is `mint spec` → `mint exec init` → `mint verify` and independent reviews →
`mint done` → `mint receipt verify`. Run `mint <command> --help` for current flags. The canonical
contract and examples live in mint's `AGENTS.md` at https://github.com/3li7alaki/mint.
