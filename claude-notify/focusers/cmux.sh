#!/bin/bash
# Send notification via cmux native notification system.
# Usage: cmux.sh <tty> [pid]
#
# cmux has built-in notification support with panel highlighting
# and a notification panel (⌘I). This script uses the cmux CLI
# to trigger a native notification — no terminal-notifier needed.
#
# Note: This script is called by terminal-notifier -execute as a fallback.
# Normally, notify.py calls `cmux notify` directly and skips terminal-notifier.
# This file exists for consistency with the focuser interface.

CMUX_BIN=$(command -v cmux 2>/dev/null)

if [ -n "$CMUX_BIN" ]; then
    "$CMUX_BIN" notify "Claude Code 需要你的关注" 2>/dev/null
fi
