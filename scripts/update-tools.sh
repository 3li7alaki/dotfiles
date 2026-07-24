#!/usr/bin/env bash
# Pull latest for every enabled tool: `setup.sh --update` runs `brew upgrade` and re-runs
# each tool's installer (curl/npx installers fetch latest). Wired to a weekly cron; also
# runnable by hand any time.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup.sh" --update
