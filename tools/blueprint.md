# blueprint: the spec layer above the code

> Grill the idea until it has no holes, then hand your agents a spec they can't misread.

blueprint is a CLI on PATH. It owns definition: the question bank, specs, requirement slugs,
the unknowns register, conventions, review lenses, and the repo-side gates that keep code
traceable to a requirement. It never issues a completion verdict, that is [[mint]]'s floor,
and it never owns tickets or worktrees, that is the driver's.

Three layers, no overlap: drivers organize work, blueprint defines it, mint certifies it done.

In a repo with a `blueprint/` directory, never open those files with a file reader. They are
written to be parsed and the CLI returns the four lines you need instead of a hundred and fifty:

```bash
blueprint req next                          # what is startable right now
blueprint req show <feature>/<slug>         # confidence, EARS line, fit line
blueprint open list --blocking <feature>    # must be empty before starting
blueprint spec show <feature> --section surfaces
blueprint check                             # coverage, orphan, budget, blocked, drift, dash
blueprint mint <feature>/<slug>             # prints the mint unit command, unexecuted
```

Mutations go through the CLI too (`req add`, `amend`, `open add`, `decide`). Hand-editing
`blueprint/spec/` is blocked by a hook, and the block is correct: a spec edited to match the
code it produced is the implementation grading its own homework.

Every command takes `--json`. Human output is never the integration protocol.

Three rules that are not negotiable, because they are the whole point:

1. A `derived` requirement was inferred, not stated, and is unimplementable until a human
   confirms it.
2. An unanswered question goes to `OPEN.md` with its cost line and blocks what it names.
   Never infer the missing answer to unblock yourself.
3. Never write an em dash or an en dash. The `dash` gate fails on one.

Run `blueprint --help` for the current surface. The contract lives in the repo's `AGENTS.md`
and `docs/cli.md` at https://github.com/3li7alaki/blueprint.
