---
name: handoff
description: Use when the user asks for a handoff, a continuation prompt, a context transfer, or a baton for a fresh session, including "/handoff", "hand this off", "write me a prompt to carry this on elsewhere", or when a session is ending with work still in flight. Also use when a context checkpoint hook says the session has grown enough to be worth checkpointing. Produces a self-contained continuation prompt as a file plus the clipboard. Not for summarizing finished work, git log already holds that.
---

# Handoff

Write a prompt that lets a fresh session, possibly on another harness or another
machine, carry this work on without asking anyone what anything meant.

The session that reads it cannot ask you a follow-up question. Everything it needs
either stands on its own or is lost.

## 1. Read the intent

`$ARGUMENTS` is a free string, not a mode. It steers emphasis:

| argument | shape |
|---|---|
| (empty) | mid-flight. Same task carries on. |
| "done, what next" | scope closed. What is now unblocked, what is still open. |
| "just the auth bug" | one subproblem. Everything else dropped. |
| "for codex", "for another box" | assume no local CLIs and no env vars, inline more. |
| "loop", "baton", "headless", "unattended" | autonomous. Changes the paste block, see section 4. |

Intent steers what to emphasize. It never suppresses dirty state, a failed gate,
unresolved risk, or a decision the user still owes. Those appear in every handoff.

## 2. Gather state

Run these. Do not write any of it from memory.

```sh
git rev-parse --show-toplevel
git rev-parse --short HEAD
git branch --show-current
git status --porcelain
git diff --stat
```

If `blueprint`, `mint`, or SlayZone are in play, capture their identifiers only.
Do not paste their contents: the receiving session runs the CLI and gets the
current answer, whereas a pasted copy is stale the moment it is written.

## 3. Write the file

```
${TMPDIR:-/tmp}/handoff/<repo-basename>/<session-id>-<YYYYMMDD-HHMMSS>.md
```

Temp, deliberately, so these expire on their own. A handoff is consumed within
minutes or hours and is actively misleading after that: it names a HEAD, a dirty
file list and a next action that the repo has already moved past. Keeping a
permanent archive of them would mean keeping a pile of confident, wrong files. The
transcript is the durable record, not this.

On macOS `$TMPDIR` is per-user and already `0700`, which is better than `/tmp`
(world-writable and sticky). Set `HANDOFF_STATE_DIR` if you genuinely want them kept.

The session id is what makes two concurrent sessions in one repo unable to
overwrite each other. If you cannot determine it, use `$$`.

Create the directory `0700` and the file `0600` before writing:

```sh
mkdir -p "$dir" && chmod 700 "$dir" && install -m 600 /dev/null "$f"
```

If that path is not writable, which happens under some sandboxed runs, fall back to
`/tmp/handoff/<repo-basename>/` with the same modes and name, and say plainly in your
report that it was staged there and why. Do not silently pick a different location,
and do not give up on writing the file: an unwritable preferred path is not a reason
to lose the handoff.

`hooks/handoff-checkpoint.sh` looks for the file here to know a checkpoint actually
happened. If you write it somewhere else, the hook keeps asking.

Every section below is REQUIRED. If a section is genuinely empty, write
`none known` or `not verified`. Never drop one: a section you forgot and a section
with nothing in it look identical to the reader, and one of them is a lie.

### Template

    # Handoff: <one line, what this is>

    Written <ISO timestamp> from <repo root> on <branch> @ <short sha>.
    Everything below was true then. Verify before acting on it.

    ## Intent
    <one or two lines. What the next session is for.>

    ## State
    branch:    <branch> @ <sha>
    worktree:  <absolute repo root>
    clean:     <yes | no>

    Uncommitted changes, and what each one is for:
    - path/to/file.ts    <what this edit does, and whether it is finished>
    - path/to/other.py   <same>

    <A count of dirty files is worthless. /clear does not touch the working tree,
    so the edits survive; what does not survive is knowing which hunks are
    deliberate, which are scaffolding, and which are a half-finished refactor.
    That is what this section is for. Without it the next session "tidies up" real
    work or mistakes a broken intermediate state for a finished one.>

    <If blueprint / mint / slay are in play, one line each, plus a plain-language
    fallback so a machine without those CLIs still knows what the identifier meant:>
    blueprint: auth/token-refresh   (blueprint req show auth/token-refresh)
               means: <one line>
    mint:      7c2f188-a3           (mint receipt verify 7c2f188-a3)
               means: <one line>
    slay:      <task id>

    ## Decisions
    <Each decision with its WHY. The why is the entire point. Without it the next
    session reopens a settled question and you pay for it twice. If a decision was
    the user's call rather than yours, say so, so it does not get relitigated.>

    ## Traps
    <Approaches tried that failed, and why they failed. The most valuable section
    here, because it is the only content that is not recoverable from the repo.
    Be specific: "X does not work because Y", never "avoid X".>

    ## Verified
    <Commands actually run and what they actually printed.
    "pytest tests/auth -q -> 14 passed". Nothing goes here that was not observed.>

    ## Assumed
    <Load-bearing guesses that were never checked. Anything the work rests on that
    could turn out false. An empty Assumed section usually means dishonesty rather
    than certainty.>

    ## Subagent findings
    <Conclusions from delegated work. Those turns are not in the transcript the next
    session inherits, so unrecorded means gone.>

    ## Next action
    <ONE concrete thing. A path and a verb, not a theme.>

    ## ---- paste below this line ----
    <see section 4>

## 4. The paste block

Two endings. Pick by intent, never mix them up.

**Interactive** (the default):

> Read every file named above before doing anything. Then confirm what you
> understand the state to be, and wait for my instructions.

**Autonomous** (intent mentions a loop, baton, headless, or unattended run):

> Read every file named above, then carry out the Next action. Stop and report if
> anything in State no longer matches what you find.

An autonomous run that gets the interactive ending waits forever for a user message
that is never coming. That is a hang, not a handoff.

## 5. Gate, then report

Before you say one word about clearing, check:

- [ ] the file exists and is non-empty
- [ ] it names the repo root, branch, and HEAD you just read
- [ ] every path it references exists on disk
- [ ] Next action is a specific thing, not a topic
- [ ] no section was dropped
- [ ] no credential, token, key, or private URL is in it

You are authoring this file, not dumping a transcript, so nothing lands in it that
you did not choose to put there. Keep it that way. If `gitleaks` is on PATH,
`gitleaks detect --no-git --source <file>` is a cheap second pair of eyes.

Then copy it, best effort, and never let a clipboard failure read as success:

```sh
pbcopy < "$f" 2>/dev/null || wl-copy < "$f" 2>/dev/null \
  || xclip -selection clipboard < "$f" 2>/dev/null \
  || echo "clipboard unavailable"
```

Report exactly this and nothing more, naming the reset that belongs to the surface
you are actually running on:

    handoff: <absolute path>
    clipboard: yes | no

    Read it before you reset. <reset line>

Reset line, by surface:

- Claude Code: "/clear leaves this session on disk and `claude --resume` brings it
  back, but the fresh session only gets this file."
- Codex, opencode, or anything else: "start a new session and open with this file."

Do not tell a Codex user to run `/clear`. If you cannot tell which surface you are on,
use the generic line.

## Rules

- Forward-looking. Git holds the record of what was done. This holds what to do
  next and why. Do not write a diary.
- Declarative, not imperative. "The retry path is not implemented", not "implement
  the retry path".
- Never restate CLAUDE.md, the routing banner, or anything the next session loads
  on its own. It already has those, and repeating them spends the window you are
  trying to save.
- Identifiers are references, not copies.
- No em dash, no en dash.
