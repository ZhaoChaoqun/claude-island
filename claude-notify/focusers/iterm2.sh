#!/bin/bash
# Focus iTerm2 session by TTY.
# Usage: iterm2.sh <tty> [pid]
#
# Finds the iTerm2 session whose TTY matches, selects it,
# and brings the containing window to front.

TTY="$1"
[ -z "$TTY" ] && exit 1

# Escape backslashes and double quotes for AppleScript
ESCAPED_TTY=$(printf '%s' "$TTY" | sed 's/\\/\\\\/g; s/"/\\"/g')

osascript -e "
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
"
