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
        sections.append("""## SlayZone + T3 Code

T3 Code is the primary chat surface, not the task orchestrator. For work associated
with SlayZone, open T3 from the Slay task terminal and use the task's existing working
directory. Never create a second T3 worktree for a task already isolated by SlayZone.

These rules activate at runtime only when `$SLAYZONE_TASK_ID` is present:

- Load the `slay` skill before running the CLI; discover commands from the installed
  CLI's help instead of relying on a copied command list.
- Use `$SLAYZONE_TASK_ID` and `$SLAYZONE_PROJECT_ID` as the current task context.
- Keep SlayZone responsible for Kanban state, task worktrees, and shipping.
- Keep T3 responsible for the conversation, harness/model selection, and diff review.
- The underlying Codex or Claude agent performs Slay operations; T3 needs no plugin.

When the Slay environment variables are absent, treat this as an ordinary T3/Codex or
Claude session and do not infer a Slay task from the current directory.""")

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
