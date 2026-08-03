#!/usr/bin/env python3
"""Fold a merge round's slug groups into the accumulated alias map.

The model is asked which slugs name the same rule. It is NOT asked which one wins. Two
rounds over the same input agreed on the grouping almost everywhere and disagreed on the
canonical, and rebuilding the map from scratch each round turned that disagreement into
two-cycles (caveman-mode -> caveman-chat -> caveman-mode). promote() applies the map exactly
once, so a cycle folds to an arbitrary member instead of a canonical, and a third round just
resamples the same coin.

So: treat every pair either round produced as an edge, union-find the components, and elect
the canonical here, deterministically. Two properties fall out. The map is flat, which is
what makes promote()'s single pass correct by construction. And rounds accumulate instead of
overwriting, so more rounds can only add folds.

Election is by distinct session count, ties lexicographic. That picks the phrasing the
developer actually used most, not the prettiest name; the staging file shows the claim
underneath, so the slug is a key, not a headline.
"""

import argparse
import collections
import json
import os
import pathlib
import sys
import tempfile


def elect(edges, sessions):
    """Union-find over `edges`, returning a flat {member: canonical} map with no self-entries."""
    parent: dict = {}

    def find(x):
        parent.setdefault(x, x)
        root = x
        while parent[root] != root:
            root = parent[root]
        while parent[x] != root:          # path compression, so a long chain stays cheap
            parent[x], x = root, parent[x]
        return root

    for a, b in edges:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    groups = collections.defaultdict(list)
    for slug in parent:
        groups[find(slug)].append(slug)

    out = {}
    for members in groups.values():
        if len(members) < 2:
            continue
        canonical = min(members, key=lambda s: (-len(sessions.get(s, ())), s))
        for s in members:
            if s != canonical:
                out[s] = canonical
    return out


def read_edges(path: pathlib.Path):
    """A round file is one {canonical, aliases} object per line. Only the pairing survives."""
    if not path or not path.is_file():
        return []
    edges = []
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        canonical, aliases = obj.get("canonical"), obj.get("aliases")
        if not canonical or not isinstance(aliases, list):
            continue
        edges += [(canonical, a) for a in aliases if isinstance(a, str) and a]
    return edges


def session_counts(candidates: pathlib.Path):
    sessions = collections.defaultdict(set)
    for line in candidates.read_text().splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("slug"):
            sessions[row["slug"]].add(row.get("session"))
    return sessions


def write_map(path: pathlib.Path, mapping: dict) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".slugmap-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(mapping, fh, indent=1, sort_keys=True)
        os.replace(tmp, path)
    except BaseException:
        pathlib.Path(tmp).unlink(missing_ok=True)
        raise


def self_check() -> int:
    s = {"a": {"1", "2", "3"}, "b": {"1"}, "c": {"1"}, "d": {"1"}}

    # Opposite elections across two rounds must not survive as a cycle.
    m = elect([("a", "b"), ("b", "a")], s)
    assert m == {"b": "a"}, f"cycle survived: {m}"
    assert not (set(m) & set(m.values())), "map is not flat"

    # Rounds accumulate: a group each round saw only half of comes out whole.
    m = elect([("a", "b"), ("c", "b"), ("d", "c")], s)
    assert m == {"b": "a", "c": "a", "d": "a"}, f"union did not accumulate: {m}"

    # A chain flattens, so promote()'s single pass lands on the canonical, not a midpoint.
    m = elect([("b", "c"), ("c", "d")], {"b": {"1", "2"}, "c": {"1"}, "d": {"1"}})
    assert m == {"c": "b", "d": "b"}, f"chain did not flatten: {m}"

    # Election is by session count, then lexicographic. Never by model preference.
    assert elect([("b", "a")], s) == {"b": "a"}, "ignored session counts"
    assert elect([("b", "c")], {"b": {"1"}, "c": {"1"}}) == {"c": "b"}, "tie not lexicographic"

    # A dead round leaves the map alone rather than wiping it.
    assert elect([], s) == {}, "empty round produced edges"

    print("self-check ok")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("candidates", nargs="?", help="candidates.jsonl, for the session counts")
    ap.add_argument("slugmap", nargs="?", help="alias map to accumulate into, rewritten in place")
    ap.add_argument("round", nargs="?", help="this round's {canonical, aliases} lines")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args()

    if args.self_check:
        return self_check()
    if not (args.candidates and args.slugmap):
        ap.error("candidates and slugmap are required")

    slugmap = pathlib.Path(args.slugmap)
    prior = {}
    if slugmap.is_file() and slugmap.stat().st_size:
        try:
            prior = json.loads(slugmap.read_text())
        except json.JSONDecodeError:
            print(f"  ! {slugmap} is not JSON, starting from this round alone", file=sys.stderr)

    edges = list(prior.items()) + read_edges(pathlib.Path(args.round) if args.round else None)
    merged = elect(edges, session_counts(pathlib.Path(args.candidates)))

    if len(merged) < len(prior):
        # Only reachable if a slug vanished from the map's own keys, which accumulation
        # cannot do. Worth saying out loud rather than silently shrinking the map.
        print(f"  ! map shrank, {len(prior)} to {len(merged)}", file=sys.stderr)

    write_map(slugmap, merged)
    print(f"  {len(merged)} alias(es) in {len(set(merged.values()))} group(s), "
          f"was {len(prior)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
