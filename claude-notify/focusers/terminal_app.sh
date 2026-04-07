#!/bin/bash
# Focus Terminal.app tab by TTY.
# Usage: terminal_app.sh <tty> [pid]
#
# Terminal.app has tabs but no panes. Finds the tab whose TTY matches,
# selects it, and brings the window to front.

TTY="$1"
[ -z "$TTY" ] && exit 1

ESCAPED_TTY=$(printf '%s' "$TTY" | sed 's/\\/\\\\/g; s/"/\\"/g')

osascript -e "
tell application \"Terminal\"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            if tty of t is \"$ESCAPED_TTY\" then
                set selected tab of w to t
                set index of w to 1
                return true
            end if
        end repeat
    end repeat
end tell
return false
"
