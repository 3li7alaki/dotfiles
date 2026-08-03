#!/usr/bin/env python3
"""Redact credentials from Claude Code transcript history, in place.

Transcripts under ~/.claude/projects accumulate whatever passed through a session:
.env dumps, docker run lines, OAuth callbacks, panel output. They sit unencrypted and
every tool that reads that directory sees them. This rewrites the leaked VALUES and
leaves everything else byte-identical.

Dry run by default. `--apply` writes, and only after every rewritten line is confirmed
to still parse as JSON. Back the directory up first; there is no undo here.

Precision beats coverage. A false positive silently corrupts real conversation history,
so placeholders, shell variable references, and template markers are deliberately kept:
redacting "your_api_key_here" gains nothing and destroys the sentence around it.
"""

import argparse
import contextlib
import json
import os
import pathlib
import re
import sys
from collections import Counter

MASK = "[REDACTED]"

# Vendor formats. These are unambiguous: the prefix plus length is the credential.
VENDOR = [
    ("linear",        re.compile(r"\blin_api_[A-Za-z0-9]{32,}")),
    ("github",        re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}")),
    ("github-pat",    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}")),
    ("slack-app",     re.compile(r"\bxapp-[0-9]-[A-Za-z0-9-]{16,}")),
    ("stripe-whsec",  re.compile(r"\bwhsec_[A-Za-z0-9]{16,}")),
    ("aws-key-id",    re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("resend",        re.compile(r"\bre_[A-Za-z0-9]{8,}_[A-Za-z0-9]{16,}")),
    ("openai",        re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{32,}")),
    ("stripe",        re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9]{16,}")),
    ("slack",         re.compile(r"\bxox[abps]-[A-Za-z0-9-]{16,}")),
    ("jwt",           re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    # Whole PEM block, not just the header. A transcript holds the entire key on one physical
    # line (the newlines are \n escapes inside a JSON string), so redacting only the BEGIN
    # marker leaves the base64 body sitting right there. The second pattern cleans up exactly
    # that half-scrubbed state, left behind by an earlier header-only version of this rule.
    # The body class allows a bare backslash rather than a `\n` alternation: transcripts carry
    # PEM newlines at whatever escape depth the capture happened at, and a nested-JSON capture
    # produces `\\n` (two backslashes). Matching only single-escape depth silently left a live
    # RSA key in place, so treat backslash as an ordinary body character.
    ("private-key",   re.compile(r"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----"
                                 r"[A-Za-z0-9+/=\s\\]*?"
                                 r"-----END (?:[A-Z ]+ )?PRIVATE KEY-----")),
    ("private-key-body", re.compile(r"\[REDACTED\][A-Za-z0-9+/=\s\\]*?"
                                    r"-----END (?:[A-Z ]+ )?PRIVATE KEY-----")),
    ("private-key-header", re.compile(r"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----")),
    ("oauth-code",    re.compile(r"(?<=[?&]code=)[A-Za-z0-9._-]{16,}")),
]

# Password embedded in a connection string: redact the password field only, so the host,
# database name, and shape of the URL survive for context.
DSN = re.compile(r"\b((?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp)://[^:@\s/]+:)([^@\s/]{4,})(?=@)")

# Assignment form, for secrets with no recognizable vendor prefix.
# The quote groups are `(?:\\?["'])?`, never a bare optional backslash: transcripts are JSON,
# so a lone `\` is the head of an escape. Letting it be consumed made an empty NAME= match the
# `\n` and swallow the following line as its "value", which the JSON guard caught.
# The name is wrapped in an atomic group and its filler runs are bounded. Unbounded
# `[A-Z0-9_]*` on both sides of the alternation backtracks super-linearly against a long
# run of uppercase and underscores that never reaches a delimiter, and transcript lines
# run to tens of kilobytes, so that is a hang on real input rather than a theoretical one.
ASSIGN = re.compile(
    r"((?>[A-Z0-9_]{0,40}(?:SECRET|PASSWORD|API_?KEY|ACCESS_TOKEN|AUTH_TOKEN|PRIVATE_KEY)[A-Z0-9_]{0,40})"
    r"(?:\\?[\"'])?[ \t]*[:=][ \t]*(?:\\?[\"'])?)"
    r"([^\s\"'\\,;)}]{8,})"
)

# Names that contain a secret-ish word but never hold a secret: event enums, paths, and
# tuning knobs. Without this, PASSWORD_STORE_DIR and SECURITY_PASSWORD_CHANGED get redacted,
# which corrupts real content for no security gain. Found by auditing what the rule matched.
NAME_DENY = re.compile(
    r"(?:_DIR|_PATH|_FILE|_NAME|_TYPE|_FIELD|_HEADER|_LENGTH|_ROUNDS|_TTL|_EXPIRY"
    r"|_ALGORITHM|_ENABLED|_REQUIRED|_MIN|_MAX|_CREATED|_REQUESTED|_CHANGED|_RESET"
    r"|_UPDATED|_DELETED|_FAILED|_SUCCEEDED|_EXPIRED|_SENT|_VERIFIED)$"
)

# A value matching any of these is a placeholder, a variable reference, or a literal the
# developer typed as an example. Redacting it destroys meaning and protects nothing.
PLACEHOLDER = re.compile(
    r"^(?:\$|<|\{\{|%|your[_-]|my[_-]|some[_-]|example|sample|placeholder|changeme|change[_-]me"
    r"|dev[_-]only|dev[_-]|local[_-]|seed[_-]|dummy|fake|test[_-]|xxx|\.\.\.|null|undefined|true|false"
    r"|process\.env|z\.string|os\.environ|REDACTED|\[REDACTED\])",
    re.IGNORECASE,
)
# Real secrets have entropy. A value that is one lowercase word is prose, not a credential.
LOW_ENTROPY = re.compile(r"^[a-z]+$|^[A-Z_]+$")


def is_placeholder(value: str) -> bool:
    return bool(PLACEHOLDER.match(value) or LOW_ENTROPY.match(value) or value.endswith("_HERE"))


def scrub_line(line: str, counts: Counter) -> str:
    for name, pattern in VENDOR:
        line, n = pattern.subn(MASK, line)
        if n:
            counts[name] += n

    def dsn_sub(m: re.Match) -> str:
        if is_placeholder(m.group(2)):
            return m.group(0)
        counts["dsn-password"] += 1
        return m.group(1) + MASK

    line = DSN.sub(dsn_sub, line)

    def assign_sub(m: re.Match) -> str:
        name = m.group(1).strip().rstrip("=:\"'\\ ")
        if NAME_DENY.search(name) or is_placeholder(m.group(2)):
            return m.group(0)
        counts["assignment"] += 1
        return m.group(1) + MASK

    return ASSIGN.sub(assign_sub, line)


def process(path: pathlib.Path, apply: bool, counts: Counter) -> int:
    """Returns the number of lines changed. Writes only when apply and nothing broke."""
    try:
        original = path.read_text(encoding="utf-8", errors="surrogateescape")
    except OSError as exc:
        print(f"  ! unreadable, skipped: {path} ({exc})", file=sys.stderr)
        return 0

    out, changed = [], 0
    for lineno, line in enumerate(original.splitlines(keepends=True), 1):
        scrubbed = scrub_line(line, counts)
        if scrubbed != line:
            # A rewrite that breaks the JSON would corrupt session state. Drop the whole
            # file rather than write a torn transcript.
            if line.strip():
                try:
                    json.loads(scrubbed)
                except json.JSONDecodeError as exc:
                    print(f"  ! {path.name}:{lineno} would break JSON ({exc.msg}), file skipped",
                          file=sys.stderr)
                    return 0
            changed += 1
        out.append(scrubbed)

    if changed and apply:
        # mkstemp, not a deterministic ".scrubtmp": it opens O_CREAT|O_EXCL|O_WRONLY at 0600,
        # so a pre-planted symlink at a guessable path cannot redirect the write, and the
        # window never exposes transcript content at the umask default. Then copy the
        # original mode across, because transcripts are 0600 and a fresh file must not
        # silently widen them.
        import tempfile
        mode = path.stat().st_mode & 0o777
        fd, tmpname = tempfile.mkstemp(dir=path.parent, prefix=".scrub-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape") as fh:
                fh.write("".join(out))
            os.chmod(tmpname, mode)
            os.replace(tmpname, path)
        except BaseException:
            with contextlib.suppress(OSError):
                os.unlink(tmpname)
            raise
    return changed


def self_check() -> int:
    """Covers the failure modes an AppSec pass found, so they cannot silently return."""
    import tempfile as _tf, time
    from collections import Counter as _C

    # Vendor formats, including the four a first version missed.
    for token in ["github_pat_" + "A" * 24, "xapp-1-" + "A" * 20, "whsec_" + "A" * 20,
                  "lin_api_" + "b" * 40, "ghp_" + "c" * 40, "AKIA" + "B" * 16]:
        assert MASK in scrub_line(f"KEY={token}", _C()), f"missed vendor token: {token[:12]}"

    # Placeholders and non-credential names survive untouched.
    for keep in ['API_KEY="your_api_key_here"', "PASSWORD_STORE_DIR=/home/u/.password-store",
                 "SECURITY_PASSWORD_CHANGED=some_event_name", "SECRET=$MY_VAR"]:
        assert scrub_line(keep, _C()) == keep, f"over-redacted: {keep}"

    # Whole PEM block goes, at any escape depth, not just its header.
    for esc in ["\\n", "\\\\n"]:
        pem = f"-----BEGIN RSA PRIVATE KEY-----{esc}MIIEabc123{esc}-----END RSA PRIVATE KEY-----"
        assert "MIIEabc123" not in scrub_line(pem, _C()), f"PEM body survived at escape {esc!r}"

    # A long secret-ish name with no delimiter must not blow up the matcher.
    start = time.monotonic()
    scrub_line("SECRET" + "_ABCDEFGH" * 4000, _C())
    assert time.monotonic() - start < 1.0, "ASSIGN regex backtracks super-linearly"

    # Applying preserves the original mode instead of writing at the umask default.
    with _tf.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "t.jsonl"
        f.write_text('{"a":"AKIA' + "B" * 16 + '"}\n')
        os.chmod(f, 0o600)
        assert process(f, True, _C()) == 1
        assert os.stat(f).st_mode & 0o777 == 0o600, "apply widened the file mode"
        assert "AKIA" not in f.read_text()
        assert not list(pathlib.Path(d).glob(".scrub-*")), "temp file left behind"

    print("self-check ok")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", nargs="?", default=str(pathlib.Path.home() / ".claude" / "projects"))
    ap.add_argument("--apply", action="store_true", help="write changes (default is a dry run)")
    ap.add_argument("--self-check", action="store_true", help="run assertions and exit")
    args = ap.parse_args()

    if args.self_check:
        return self_check()

    root = pathlib.Path(args.root)
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    counts: Counter = Counter()
    files = sorted(root.rglob("*.jsonl"))
    touched = total_lines = 0
    for path in files:
        n = process(path, args.apply, counts)
        if n:
            touched += 1
            total_lines += n

    mode = "APPLIED" if args.apply else "DRY RUN (nothing written)"
    print(f"\n{mode}")
    print(f"  scanned {len(files)} files, {touched} contain credentials, {total_lines} lines affected")
    for name, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"    {name:<14} {n}")
    if not args.apply and touched:
        print("\n  re-run with --apply to write. Back the directory up first.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
