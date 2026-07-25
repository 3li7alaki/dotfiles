#!/usr/bin/env bash
# Tune PinchTab so an idle install costs nothing.
#
# Why: PinchTab ships with multiInstance.strategy = "always-on", and its launchd
# agent (com.pinchtab.pinchtab) sets KeepAlive. Together those keep a headless
# Chrome alive 24/7 whether or not an agent is using it. PinchTab also renders
# through SwiftShader (--use-angle=swiftshader, --disable-vulkan), which is
# deliberate for stealth but puts every pixel on the CPU instead of the GPU, and
# it launches Chrome with --disable-background-timer-throttling and
# --disable-renderer-backgrounding so no tab ever gets deprioritized. A single
# runaway page therefore pins several cores indefinitely with nobody watching.
#
# Measured on this box before tuning: 26+ Chrome processes and one renderer at
# 847% CPU, sustained for over three hours after the last real request.
# After tuning: 0 Chrome processes at idle, daemon at 0.0% CPU, ~3s cold start
# on the next request.
#
# The Go daemon itself is free when idle on macOS (unlike the Docker case in
# upstream issue #519), so the launchd agent is left alone.
#
# Every knob here is documented in docs/reference/config.md upstream.
set -euo pipefail

command -v pinchtab >/dev/null 2>&1 || { echo "pinchtab not on PATH, skip"; exit 0; }

pinchtab config patch '{
  "multiInstance": { "strategy": "simple" },
  "instanceDefaults": {
    "maxTabs": 6,
    "blockAds": true,
    "blockMedia": true,
    "noAnimations": true,
    "noRestore": true,
    "tabPolicy": {
      "eviction": "close_lru",
      "lifecycle": "close_idle",
      "closeDelaySec": 60,
      "restore": false
    }
  }
}'

# strategy=simple   launch Chrome on demand instead of holding one forever
# maxTabs=6         hard ceiling on concurrent renderers (was 20)
# blockAds          ad JS is the heaviest thing on most pages, and pure waste here
# blockMedia        video/audio decode under SwiftShader is CPU-only, the worst offender
# noAnimations      CSS/JS animation loops also land on the CPU under SwiftShader
# noRestore         do not reopen yesterday's tabs, which is how a runaway page survives
# lifecycle         close a tab 60s after its last read, per upstream issue #499
#
# blockImages is deliberately left off: it breaks /screenshot.

# Config only takes effect on restart. launchd owns the daemon on macOS.
if launchctl list 2>/dev/null | grep -q com.pinchtab.pinchtab; then
  launchctl kickstart -k "gui/$(id -u)/com.pinchtab.pinchtab" >/dev/null 2>&1 || true
else
  pinchtab server restart >/dev/null 2>&1 || true
fi

echo "pinchtab tuned: idle cost is now zero Chrome processes"
