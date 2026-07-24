#!/usr/bin/env python3
"""Render the config.toml add-on catalog inside README.md."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
import tomllib

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
CONFIG = ROOT / "config.toml"
START = "<!-- catalog:start -->"
END = "<!-- catalog:end -->"


def linked(name: str, url: str | None) -> str:
    return f"[{name}]({url})" if url else name


def enabled(value: bool) -> str:
    return "on" if value else "off"


def table(headers: list[str], rows: list[list[str]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    lines.extend("| " + " | ".join(row) + " |" for row in rows)
    return "\n".join(lines)


def render(data: dict) -> str:
    app_rows = []
    for name, item in data.get("apps", {}).items():
        platforms = ", ".join(
            platform for platform in ("darwin", "linux") if item.get(f"probe_{platform}")
        )
        app_rows.append([
            linked(name, item.get("homepage")),
            "Desktop app + CLI",
            platforms,
            enabled(item.get("enabled", False)),
            item.get("desc", ""),
        ])

    tool_rows = []
    for name, item in data.get("tools", {}).items():
        platforms = item.get("os", "Linux / macOS")
        tool_rows.append([
            linked(name, item.get("homepage")),
            "CLI",
            platforms,
            enabled(item.get("enabled", False)),
            item.get("desc", ""),
        ])

    stow_rows = []
    for name, item in data.get("stow", {}).items():
        stow_rows.append([
            linked(name, item.get("homepage")),
            item.get("target", "HOME"),
            ", ".join(item.get("requires_tools", [])) or "stow",
            enabled(item.get("enabled", False)),
            item.get("desc", ""),
        ])

    skill_types = {
        "plugin": "Claude plugin",
        "npx-plugin": "Skill bundle",
        "mcp": "MCP server",
        "symlink": "Repo skill",
    }
    skill_rows = []
    for name, item in data.get("skills", {}).items():
        skill_class = skill_types.get(item.get("type"), item.get("type", "skill"))
        if item.get("type") == "symlink" and len(item.get("providers", [])) > 1:
            skill_class = "Shared agent skill"
        skill_rows.append([
            linked(name, item.get("homepage")),
            skill_class,
            enabled(item.get("enabled", False)),
            item.get("desc", ""),
        ])

    integration_rows = []
    for name, item in data.get("integrations", {}).items():
        requirements = ", ".join(item.get("requires_apps", [])) or "none"
        integration_rows.append([
            name,
            requirements,
            enabled(item.get("enabled", False)),
            item.get("desc", ""),
        ])

    plugins = data.get("plugins", {})
    plugin_home = plugins.get("homepage")
    plugin_rows = []
    for item in plugins.get("enabled", []):
        if isinstance(item, str):
            name, description = item, ""
        else:
            name, description = item["name"], item.get("desc", "")
        display = name.split("@", 1)[0]
        plugin_rows.append([linked(display, plugin_home), "Claude plugin", "on", description])

    wiring_rows = []
    for name, item in data.get("hooks", {}).items():
        wiring_rows.append([
            name,
            "Claude hook",
            enabled(item.get("enabled", False)),
            item.get("desc", ""),
        ])
    for name, item in data.get("daemons", {}).items():
        wiring_rows.append([
            name,
            f"User daemon ({item.get('os', 'all')})",
            enabled(item.get("enabled", False)),
            item.get("desc", ""),
        ])
    for name, item in data.get("cron", {}).items():
        wiring_rows.append([
            name,
            "Scheduled task",
            enabled(item.get("enabled", False)),
            item.get("desc", ""),
        ])

    parts = [
        "### Desktop apps",
        "",
        table(["Add-on", "Class", "Platform", "Default", "Purpose"], app_rows),
        "",
        "### Command-line tools",
        "",
        table(["Add-on", "Class", "Platform", "Default", "Purpose"], tool_rows),
        "",
        "### Stow-managed configurations",
        "",
        table(["Package", "Target", "Requires", "Default", "Purpose"], stow_rows),
        "",
        "### Skills and MCP integrations",
        "",
        table(["Add-on", "Class", "Default", "Purpose"], skill_rows),
        "",
        "### Cross-app integrations",
        "",
        table(["Integration", "Requires", "Default", "Ownership"], integration_rows),
        "",
        "### Official Claude plugins",
        "",
        table(["Add-on", "Class", "Default", "Purpose"], plugin_rows),
        "",
        "### Automation and wiring",
        "",
        table(["Component", "Class", "Default", "Purpose"], wiring_rows),
    ]
    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if README is stale")
    args = parser.parse_args()

    data = tomllib.loads(CONFIG.read_text())
    readme = README.read_text()
    if START not in readme or END not in readme:
        raise SystemExit("README catalog markers are missing")
    before, rest = readme.split(START, 1)
    _, after = rest.split(END, 1)
    expected = f"{before}{START}\n\n{render(data)}\n\n{END}{after}"

    if args.check:
        if readme != expected:
            print("README add-on catalog is stale; run scripts/render-readme-catalog.py", file=sys.stderr)
            return 1
        return 0
    README.write_text(expected)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
