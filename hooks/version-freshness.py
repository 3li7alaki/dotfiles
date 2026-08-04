#!/usr/bin/env python3
"""PreToolUse gate: no package version reaches disk straight from training memory.

Fires on Write/Edit of a dependency manifest and on Bash install commands. Pulls every
(ecosystem, package, version) it can see out of the payload, asks `scripts/latest-version`
what the registry actually says, and blocks (exit 2) when a pin sits a whole breaking-change
version behind (see is_stale: the major post-1.0, the minor pre-1.0).

Why that threshold and not "any newer release exists": firing on every patch is noise you
learn to ignore, and being a patch or a minor behind is usually deliberate. A breaking
version behind is the actual failure mode, the model writing Next 14 idioms in 2026 because
that is where its training data ended.

Blocks ONCE per package per session (sentinel in TMPDIR). Retry the identical write and it
passes, so an intentional React-18-lockstep pin costs exactly one extra turn and needs no
flag anyone has to remember.

Silence from the resolver (offline, unknown package, registry 404) means "no opinion" and
never blocks. A gate that hard-fails when the network blips is a gate you rip out.
"""
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

MAX_LOOKUPS = 8          # cap the blocking path; the rest pass unchecked rather than stall
RESOLVER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "latest-version")

# Manifest basename → ecosystem. requirements*.txt is matched separately.
MANIFESTS = {
    "package.json": "npm",
    "pyproject.toml": "pypi",
    "Pipfile": "pypi",
    "Cargo.toml": "crates",
    "go.mod": "go",
    "composer.json": "composer",
}
JSON_DEP_KEYS = {
    "npm": ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"),
    "composer": ("require", "require-dev"),
}
VERSION_HEAD = re.compile(r"^[\s^~>=<v]*(\d+)(?:\.(\d+))?")


def major(spec):
    """Leading major number of a version spec, or None if it isn't one."""
    m = VERSION_HEAD.match(spec or "")
    return int(m.group(1)) if m else None


def minor(spec):
    m = VERSION_HEAD.match(spec or "")
    return int(m.group(2) or 0) if m else None


def is_stale(spec, latest):
    """A whole breaking-change axis behind.

    Post-1.0 that axis is the major. Pre-1.0 it is the MINOR. Semver §4 gives 0.x no
    stability guarantee, so 0.100 to 0.141 is the same distance as 14 to 16, and most of
    PyPI and crates.io lives at 0.x. Checking only the major would let that whole
    population through, which is exactly where a model's stale memory shows up.
    """
    have_maj, want_maj = major(spec), major(latest)
    if have_maj is None or want_maj is None:
        return False
    if have_maj < want_maj:
        return True
    return have_maj == want_maj == 0 and minor(spec) < minor(latest)


CARET_DEFAULT = {"crates"}          # a bare version in Cargo.toml already MEANS caret


def admits_latest(eco, spec, latest):
    """Would this spec actually install the current release?

    The strict rule for greenfield is "not behind", not "string-equals latest". `^16.0.0`
    installs 16.3.0, so it is not outdated and flagging it would be exactly the noise that
    kills a gate. `~16.0.0`, `16.0.0`, and a go.mod pin do not, so they are.

    Patch drift is always tolerated: patches ship constantly and pinning one is normal.
    """
    lat_maj, lat_min = major(latest), minor(latest)
    spec_maj, spec_min = major(spec), minor(spec)
    if lat_maj is None or spec_maj is None:
        return True
    s = (spec or "").strip()
    if s.startswith((">=", ">")) or s.startswith("*"):
        return True
    if s.startswith("^"):
        op = "^"
    elif s.startswith("~"):
        op = "~"
    else:
        op = "^" if eco in CARET_DEFAULT else "="
    if op == "^" and spec_maj > 0:
        return spec_maj == lat_maj       # caret floats the minor, but only above 1.0
    # tilde, exact, and 0.x caret are all locked to major.minor
    return spec_maj == lat_maj and spec_min == lat_min


def from_json_manifest(text, eco):
    """Structured pass: only real dependency blocks, so zero false positives.

    Only works when the payload is a whole valid document (a Write, usually). An Edit
    hands over a fragment, which falls through to the regex pass below.
    """
    try:
        doc = json.loads(text)
    except (ValueError, TypeError):
        return None
    out = []
    for block in JSON_DEP_KEYS[eco]:
        for name, spec in (doc.get(block) or {}).items():
            if not isinstance(spec, str) or name.startswith("ext-") or name == "php":
                continue
            if major(spec) is not None:
                out.append((eco, name, spec))
    return out


def from_json_fragment(text, eco):
    """Fallback for Edit fragments: `"pkg": "^1.2.3"` pairs.

    Requires a dot in the version so `"node": ">=18"` and `"port": "3000"` can't be
    mistaken for pins. Ceiling: a bare-major pin (`"react": "19"`) slips through here;
    the structured pass above catches it whenever the payload is a whole file.
    """
    out = []
    for name, spec in re.findall(r'"([@A-Za-z0-9._/-]+)"\s*:\s*"([^"]*)"', text):
        if name in ("version", "name", "packageManager", "php") or name.startswith("ext-"):
            continue
        if eco == "composer" and "/" not in name:
            continue
        if re.match(r"^[\s^~>=<v]*\d+\.\d+", spec):
            out.append((eco, name, spec))
    return out


def from_python(text):
    # requirements.txt / PEP 621 (pkg>=1.2) and poetry (pkg = "^1.2"). The operator is part
    # of the spec and must survive: `>=4.2` installs the current release, so it is a floor,
    # not a stale pin, and flagging it would be a false positive.
    out = [("pypi", n, op + v)
           for n, op, v in re.findall(r"([A-Za-z0-9._-]+)\s*(==|>=|~=|>)\s*([0-9][0-9a-zA-Z.]*)", text)]
    out += [("pypi", n, v) for n, v in re.findall(r'^\s*([A-Za-z0-9._-]+)\s*=\s*"([\^~>=]*[0-9][0-9a-zA-Z.]*)"', text, re.M)
            if n not in ("python", "version", "name", "requires-python")]
    return out


def from_cargo(text):
    # `pkg = "1.2"` and `pkg = { version = "1.2" }`.
    out = [("crates", n, v) for n, v in re.findall(r'^\s*([A-Za-z0-9_-]+)\s*=\s*"([\^~>=]*[0-9][0-9a-zA-Z.]*)"', text, re.M)]
    out += [("crates", n, v) for n, v in re.findall(r'^\s*([A-Za-z0-9_-]+)\s*=\s*\{[^}]*version\s*=\s*"([\^~>=]*[0-9][0-9a-zA-Z.]*)"', text, re.M)]
    return [t for t in out if t[1] not in ("name", "version", "edition", "rust-version", "authors", "license")]


def from_gomod(text):
    return [("go", m, v) for m, v in re.findall(r"([a-z0-9.\-]+\.[a-z]{2,}/[^\s]+)\s+(v\d[0-9a-zA-Z.\-+]*)", text)]


def from_bash(cmd):
    """Install commands that pin an explicit version."""
    out = []
    if re.search(r"\b(npm|pnpm|yarn|bun)\b.*\b(add|i|install)\b", cmd):
        for name, ver in re.findall(r"(@?[A-Za-z0-9._/-]+)@(\d[0-9a-zA-Z.\-]*)", cmd):
            out.append(("npm", name, ver))
    if re.search(r"\b(pip3?|uv|poetry)\b.*\b(install|add)\b", cmd):
        out += [("pypi", n, v) for n, v in re.findall(r"([A-Za-z0-9._-]+)==([0-9][0-9a-zA-Z.]*)", cmd)]
    if re.search(r"\bcargo\s+add\b", cmd):
        out += [("crates", n, v) for n, v in re.findall(r"([A-Za-z0-9_-]+)@(\d[0-9a-zA-Z.\-]*)", cmd)]
    if re.search(r"\bgo\s+get\b", cmd):
        out += [("go", m, v) for m, v in re.findall(r"([a-z0-9.\-]+\.[a-z]{2,}/[^\s@]+)@(v\d[0-9a-zA-Z.\-+]*)", cmd)]
    if re.search(r"\bcomposer\s+require\b", cmd):
        out += [("composer", n, v) for n, v in re.findall(r"([a-z0-9._-]+/[a-z0-9._-]+):([\^~>=]*\d[0-9a-zA-Z.\-]*)", cmd)]
    return out


def candidates(payload):
    tool = payload.get("tool_name", "")
    ti = payload.get("tool_input") or {}
    if tool == "Bash":
        return from_bash(ti.get("command", "") or "")
    if tool not in ("Write", "Edit"):
        return []
    path = ti.get("file_path", "") or ""
    base = os.path.basename(path)
    text = ti.get("content") or ti.get("new_string") or ""
    if not text:
        return []
    eco = MANIFESTS.get(base)
    if eco is None and re.match(r"^requirements.*\.txt$", base):
        eco = "pypi"
    if eco is None:
        return []
    if eco in JSON_DEP_KEYS:
        return from_json_manifest(text, eco) or from_json_fragment(text, eco)
    if eco == "pypi":
        return from_python(text)
    if eco == "crates":
        return from_cargo(text)
    if eco == "go":
        return from_gomod(text)
    return []


def existing_pins(payload):
    """What the project ALREADY pins, read off disk.

    The whole point of this gate is catching a version the model invented from memory. A
    package this repo is already on at that major is not invented, it is the project's
    existing decision, and compatibility pins live exactly there: React 18 held back for a
    peer dep, a framework frozen for a migration. Re-blocking those every session is the
    spam that gets a hook deleted.

    So: fire on a package being ADDED or moved to a new major, stay silent on one already
    pinned at that major. No allowlist file to maintain, and it cannot go stale, because
    the manifest itself is the allowlist.
    """
    ti = payload.get("tool_input") or {}
    path = ti.get("file_path")
    if not path:                     # Bash install: fall back to the manifest in cwd
        cwd = payload.get("cwd") or os.getcwd()
        paths = [os.path.join(cwd, m) for m in MANIFESTS]
    else:
        paths = [path]
    pinned = {}
    for p in paths:
        try:
            with open(p) as fh:
                disk = fh.read()
        except OSError:
            continue
        probe = {"tool_name": "Write", "tool_input": {"file_path": p, "content": disk}}
        try:
            for eco, name, spec in candidates(probe):
                pinned.setdefault((eco, name), major(spec))
        except Exception:
            continue
    return pinned


def resolve(item):
    eco, name, spec = item
    try:
        r = subprocess.run([RESOLVER, eco, name], capture_output=True, text=True, timeout=10)
        return item, r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return item, ""


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0

    try:
        items = candidates(payload)
    except Exception:
        return 0          # a parser bug must never wedge the user's editing

    # Dedupe, drop what the project already pins at this major, cap the blocking path.
    # Filtering BEFORE the lookups also means an untouched 40-dep manifest costs no network
    # at all: a formatting edit to package.json resolves nothing.
    pinned = existing_pins(payload)
    # Nothing pinned anywhere we looked means a manifest being born: `npm init`, a scaffold,
    # the first dependency of a new service. A greenfield project has no compatibility
    # history to protect, so there is no defensible reason for any dep to start behind
    # current. Strict threshold there, lenient one in a project that already exists.
    greenfield = not pinned
    seen, todo = set(), []
    for it in items:
        eco, name, spec = it
        if it[:2] in seen or pinned.get((eco, name)) == major(spec):
            continue
        seen.add(it[:2])
        todo.append(it)
    if not todo:
        return 0
    dropped = len(todo) - MAX_LOOKUPS
    todo = todo[:MAX_LOOKUPS]

    sid = payload.get("session_id") or "default"
    sentinel = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"version-freshness-{sid}")
    try:
        with open(sentinel) as fh:
            flagged = set(fh.read().split())
    except OSError:
        flagged = set()

    with ThreadPoolExecutor(max_workers=MAX_LOOKUPS) as pool:
        results = list(pool.map(resolve, todo))

    stale = []
    for (eco, name, spec), latest in results:
        if not latest:                       # unknown / offline → no opinion
            continue
        bad = (not admits_latest(eco, spec, latest)) if greenfield else is_stale(spec, latest)
        if not bad:
            continue
        if f"{eco}/{name}" in flagged:       # already blocked once this session
            continue
        stale.append((eco, name, spec, latest))

    if not stale:
        return 0

    try:
        with open(sentinel, "a") as fh:
            fh.write("".join(f"{e}/{n}\n" for e, n, _, _ in stale))
    except OSError:
        pass

    lines = [f"  {n}: you wrote {s}, current is {l}" for _, n, s, l in stale]
    if greenfield:
        headline = "BLOCKED - new project, dependencies behind current:"
        why = ("\n\nNothing here exists yet, so no compatibility reason to start behind. These"
               "\nnumbers came from training memory, which has a cutoff the registry does not."
               "\nWrite the current versions.")
    else:
        headline = "BLOCKED - stale version pin, a whole breaking-change version behind:"
        why = ("\n\nThis came from training memory, not the registry. Use the real version, or"
               "\nretry this exact write unchanged to keep the old pin deliberately (it passes"
               "\nthe second time).")
    print(
        headline + "\n" + "\n".join(lines) + why
        + "\n\nResolve the REST of the manifest too, so this costs one turn and not five:\n  "
        + "; ".join(f"latest-version {e} {n}" for e, n, _, _ in stale)
        + "\nCrossing a major changes the API as well: pull context7 docs pinned to the new"
        "\nmajor before writing code against it, never the old major's idioms from memory."
        + (f"\n({dropped} more package(s) not checked, per-call cap.)" if dropped > 0 else ""),
        file=sys.stderr,
    )
    return 2


def self_check():
    """`version-freshness.py --self-check`, offline, no registry calls.

    Covers the parsers (where every bug lives) and the staleness comparison. Extraction is
    asserted as a set of (ecosystem, package) pairs; the version spec varies by format and
    is checked separately where it matters.
    """
    def names(tool, ti):
        return {(e, n) for e, n, _ in candidates({"tool_name": tool, "tool_input": ti})}

    pkg = json.dumps({
        "name": "my-app", "version": "1.0.0",
        "packageManager": "pnpm@9.0.0",
        "engines": {"node": ">=18"},
        "dependencies": {"next": "^14.2.0", "@tanstack/react-query": "5.0.0"},
        "devDependencies": {"typescript": "~5.3.0"},
    })
    assert names("Write", {"file_path": "/a/package.json", "content": pkg}) == {
        ("npm", "next"), ("npm", "@tanstack/react-query"), ("npm", "typescript")
    }, "structured package.json: deps only, never name/version/engines/packageManager"

    # An Edit hands over a fragment, so the JSON pass fails and the regex pass runs.
    assert names("Edit", {"file_path": "/a/package.json", "new_string": '"next": "^14.2.0",'}) == {("npm", "next")}
    assert names("Edit", {"file_path": "/a/package.json", "new_string": '"port": "3000"'}) == set(), \
        "dotless values are not versions"

    reqs = candidates({"tool_name": "Write",
                       "tool_input": {"file_path": "/a/requirements.txt",
                                      "content": "fastapi==0.100.0\ndjango>=4.2"}})
    assert set(reqs) == {("pypi", "fastapi", "==0.100.0"), ("pypi", "django", ">=4.2")}, \
        "the comparison operator is part of the spec"
    assert names("Write", {"file_path": "/a/Cargo.toml",
                           "content": '[dependencies]\nserde = "1.0.100"\ntokio = { version = "1.20" }'}) == {
        ("crates", "serde"), ("crates", "tokio")}
    assert names("Write", {"file_path": "/a/go.mod",
                           "content": "require (\n\tgithub.com/spf13/cobra v1.5.0\n)"}) == {
        ("go", "github.com/spf13/cobra")}
    assert names("Write", {"file_path": "/a/composer.json",
                           "content": '"require": {"php": "^8.1", "laravel/framework": "^11.0"}'}) == {
        ("composer", "laravel/framework")}, "composer: vendor/pkg only, php skipped"

    assert names("Bash", {"command": "npm i next@14.2.0 @scope/x@1.0.0"}) == {("npm", "next"), ("npm", "@scope/x")}
    assert names("Bash", {"command": "pip install fastapi==0.100.0"}) == {("pypi", "fastapi")}
    assert names("Bash", {"command": "go get github.com/spf13/cobra@v1.5.0"}) == {("go", "github.com/spf13/cobra")}
    assert names("Bash", {"command": "ls -la"}) == set(), "non-install commands are ignored"
    assert names("Write", {"file_path": "/a/README.md", "content": '"next": "^14.0.0"'}) == set(), \
        "only manifests are parsed"

    assert major("^14.2.0") == 14 and major("v1.5.0") == 1 and major(">=4.2") == 4
    assert major("latest") is None and major("") is None and major(None) is None

    assert is_stale("^14.2.0", "16.3.0"), "a major behind"
    assert is_stale("0.100.0", "0.141.1"), "pre-1.0: the minor is the breaking axis"
    assert not is_stale("^16.1.0", "16.3.0"), "same major, behind on minor, deliberate or harmless"
    assert not is_stale("v1.5.0", "v1.10.2"), "1.x minor drift must not fire, or it's noise"
    assert not is_stale("^19.0.0", "16.3.0"), "ahead of the registry (canary, prerelease) is not stale"
    assert not is_stale("latest", "16.3.0") and not is_stale("^1.0", "")

    # Compat pins: a package the manifest already holds at that major is the project's
    # decision, not the model's memory, so it must not be re-flagged.
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        mf = os.path.join(d, "package.json")
        with open(mf, "w") as fh:
            fh.write('{"dependencies": {"react": "^18.2.0"}}')
        pins = existing_pins({"tool_input": {"file_path": mf}})
        assert pins == {("npm", "react"): 18}, pins
        # Bash has no file_path, so it falls back to the manifest in cwd.
        assert existing_pins({"cwd": d, "tool_input": {"command": "npm i react@18.2.0"}}) == {("npm", "react"): 18}
        assert existing_pins({"cwd": d, "tool_input": {}}) == {("npm", "react"): 18}
    assert existing_pins({"tool_input": {"file_path": "/nope/package.json"}}) == {}, "missing file is not an error"

    # Greenfield threshold: "not behind", which is not the same as "string-equals latest".
    assert admits_latest("npm", "^16.0.0", "16.3.0"), "caret installs the latest minor"
    assert not admits_latest("npm", "~16.0.0", "16.3.0"), "tilde is locked to the minor"
    assert not admits_latest("npm", "16.0.0", "16.3.0"), "an exact pin is a decision"
    assert admits_latest("npm", "16.3.1", "16.3.0"), "patch drift is never the point"
    assert not admits_latest("npm", "^14.2.0", "16.3.0")
    assert admits_latest("crates", "1.0.100", "1.0.229"), "a bare Cargo version means caret"
    assert not admits_latest("npm", "^0.4.0", "0.9.0"), "caret below 1.0 locks the minor too"
    assert admits_latest("pypi", ">=4.2", "6.0.7"), "a floor installs the current release"
    assert not admits_latest("pypi", "==0.100.0", "0.141.1") and not admits_latest("pypi", "~=4.2", "6.0.7")
    assert admits_latest("npm", "latest", "16.3.0")
    assert not admits_latest("go", "v1.5.0", "v1.10.2"), "go.mod pins are always exact"
    print("self-check OK")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        self_check()
    else:
        sys.exit(main())
