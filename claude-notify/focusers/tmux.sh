#!/bin/bash
# Focus tmux pane by TTY, then activate the host terminal.
# Usage: tmux.sh <tty> [pid]
#
# Two-layer jump:
#   1. Find the tmux pane matching the TTY and select it
#   2. Activate the host terminal app (iTerm2 / Terminal.app)

TTY="$1"
PID="$2"
TMUX_BIN=$(command -v tmux 2>/dev/null)

[ -z "$TMUX_BIN" ] && exit 1

# --- Step 1: Find and select the tmux pane ---

# Try TTY matching first
if [ -n "$TTY" ]; then
    TARGET=$("$TMUX_BIN" list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
        | grep "^${TTY} " \
        | head -1 \
        | awk '{print $2}')
fi

# Fallback: PID matching via process tree
if [ -z "$TARGET" ] && [ -n "$PID" ]; then
    while IFS= read -r line; do
        PANE_PID=$(echo "$line" | awk '{print $1}')
        PANE_TARGET=$(echo "$line" | awk '{print $2}')

        # Walk up from PID to check if it's a descendant of this pane's PID
        CHECK_PID="$PID"
        DEPTH=0
        while [ "$CHECK_PID" -gt 1 ] 2>/dev/null && [ "$DEPTH" -lt 20 ]; do
            if [ "$CHECK_PID" = "$PANE_PID" ]; then
                TARGET="$PANE_TARGET"
                break 2
            fi
            CHECK_PID=$(ps -p "$CHECK_PID" -o ppid= 2>/dev/null | tr -d ' ')
            DEPTH=$((DEPTH + 1))
        done
    done <<< "$("$TMUX_BIN" list-panes -a -F '#{pane_pid} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null)"
fi

[ -z "$TARGET" ] && exit 1

# Parse session:window.pane
SESSION_WINDOW="${TARGET%.*}"
"$TMUX_BIN" select-window -t "$SESSION_WINDOW" 2>/dev/null
"$TMUX_BIN" select-pane -t "$TARGET" 2>/dev/null

# --- Step 2: Activate host terminal app ---
# tmux client's parent process tells us which terminal app is hosting it.

# Find the tmux client PID
CLIENT_PID=$("$TMUX_BIN" list-clients -F '#{client_pid}' 2>/dev/null | head -1)

if [ -n "$CLIENT_PID" ]; then
    # Walk up from client PID to find the terminal app
    CHECK="$CLIENT_PID"
    DEPTH=0
    while [ "$CHECK" -gt 1 ] 2>/dev/null && [ "$DEPTH" -lt 15 ]; do
        COMM=$(ps -p "$CHECK" -o comm= 2>/dev/null | xargs basename 2>/dev/null)
        COMM_LOWER=$(echo "$COMM" | tr '[:upper:]' '[:lower:]')

        case "$COMM_LOWER" in
            iterm2|iterm|itermserver-main)
                osascript -e 'tell application "iTerm2" to activate' 2>/dev/null
                exit 0
                ;;
            terminal|terminal.app)
                osascript -e 'tell application "Terminal" to activate' 2>/dev/null
                exit 0
                ;;
        esac

        CHECK=$(ps -p "$CHECK" -o ppid= 2>/dev/null | tr -d ' ')
        DEPTH=$((DEPTH + 1))
    done
fi

# Fallback: try to activate iTerm2, then Terminal.app
osascript -e 'tell application "iTerm2" to activate' 2>/dev/null \
    || osascript -e 'tell application "Terminal" to activate' 2>/dev/null

exit 0
