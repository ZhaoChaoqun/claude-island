#!/bin/bash
# Focus iTerm2 session by TTY.
# Usage: iterm2.sh <tty> [pid]
#
# Finds the iTerm2 session whose TTY matches, selects it,
# and brings the containing window to front.

TTY="$1"
[ -z "$TTY" ] && exit 1

LOG="/tmp/claude-notify-debug.log"
echo "$(date '+%H:%M:%S') iterm2.sh called with: TTY=$1 PID=$2" >> "$LOG"

# Escape backslashes and double quotes for AppleScript
ESCAPED_TTY=$(printf '%s' "$TTY" | sed 's/\\/\\\\/g; s/"/\\"/g')

osascript_output=$(osascript -e "
tell application \"iTerm2\"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if tty of s is \"$ESCAPED_TTY\" then
                    select t
                    select s
                    set index of w to 1
                    return true
                end if
            end repeat
        end repeat
    end repeat
end tell
return false
" 2>&1)
osascript_exit=$?
echo "$(date '+%H:%M:%S') osascript exit=$osascript_exit output=$osascript_output" >> "$LOG"
