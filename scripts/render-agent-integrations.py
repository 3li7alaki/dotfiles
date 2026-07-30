#!/usr/bin/env python3
"""Render enabled cross-app and tool guidance from merged machine configuration."""

from __future__ import annotations

import argparse
from pathlib import Path
import tomllib

ROOT = Path(__file__).resolve().parent.parent


def deep_merge(destination: dict, source: dict) -> None:
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(destination.get(key), dict):
            deep_merge(destination[key], value)
        else:
            destination[key] = value


def configuration() -> dict:
    data = tomllib.loads((ROOT / "config.toml").read_text())
    local = ROOT / "config.local.toml"
    if local.exists():
        deep_merge(data, tomllib.loads(local.read_text()))
    return data


def active(data: dict, name: str) -> bool:
    integration = data.get("integrations", {}).get(name, {})
    if not integration.get("enabled", False):
        return False
    apps = data.get("apps", {})
    return all(apps.get(app, {}).get("enabled", False) for app in integration.get("requires_apps", []))


def rendered_sections(data: dict) -> list[str]:
    sections: list[str] = []
    if active(data, "slayzone-t3-workflow"):
        sections.append("""## SlayZone + T3 Code + herdr

You are the orchestrator, not the board's clerk. The human chats in T3 Code or in a
herdr pane and never files tickets by hand. Turning a request into a SlayZone task is
your job, and SlayZone cutting the worktree is what gives that task somewhere to live.

Load the `slay` skill before running the CLI, and discover subcommands and status keys
from the installed CLI's help rather than a copied command list.

Decide which of three states you are in, in this order:

**1. `$SLAYZONE_TASK_ID` is set.** You are already inside a task worktree. Use
`$SLAYZONE_TASK_ID` and `$SLAYZONE_PROJECT_ID` as the current context. Never create a
second task for work that belongs to this one, and never cut another worktree: not with
`git worktree`, not with herdr's new-worktree action, not through T3. This tree is the
one SlayZone already isolated for you.

**2. No task id, but the repo is onboarded.** The repo's AGENTS.md carries a
`# SlayZone Environment` block, written by `scripts/slay-onboard.sh`. You are at the
orchestrator's desk. When the request is real work, meaning it will edit files and
outlive a single exchange, create the task yourself:

    slay tasks create "<short imperative title>" --project <name> --status in_progress

Creating it directly in the status the automations watch is deliberate: SlayZone cuts
the worktree, then hands the same path to T3 as a project and to herdr as a workspace.
Tell the human where the work moved, then continue there. Do not open a task for a
question you can answer by reading, a one-line fix, or anything read-only. An empty
worktree costs more than it saves.

**3. No task id and no block.** Ordinary session. Do not touch SlayZone, and do not
infer a project from the current directory. Offer onboarding if the human wants it.

Across all three: SlayZone owns Kanban state, task worktrees, and shipping. T3 owns the
conversation, harness and model selection, and diff review, including from the phone.
herdr owns panes and agent state at the desk. The underlying Codex or Claude agent
performs the Slay operations; T3 needs no plugin.""")

    tool_sections = []
    for name, tool in data.get("tools", {}).items():
        guidance = tool.get("agent_guidance", "").strip()
        if tool.get("enabled", False) and guidance:
            tool_sections.append(f"### {name}\n\n{guidance}")
    if tool_sections:
        sections.append("## Tool preferences\n\n" + "\n\n".join(tool_sections))
    return sections


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--active", action="store_true", help="check whether any guidance is active")
    args = parser.parse_args()
    sections = rendered_sections(configuration())

    if args.active:
        return 0 if sections else 1

    if sections:
        print("# Active agent context\n")
        print("\n\n".join(sections))
    else:
        print("# Active agent context\n\nNo generated agent guidance is enabled on this machine.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
