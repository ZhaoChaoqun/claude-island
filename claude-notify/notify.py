#!/usr/bin/env python3
"""
claude-notify — Claude Code plugin for terminal-aware notifications.

Detects the current terminal emulator, sends a macOS notification,
and jumps to the correct terminal pane/tab when the user clicks it.

Supported terminals: iTerm2, tmux, cmux, Terminal.app
"""
import json
import os
import shutil
import subprocess
import sys

PLUGIN_ROOT = os.path.dirname(os.path.abspath(__file__))
FOCUSERS_DIR = os.path.join(PLUGIN_ROOT, "focusers")


# ---------------------------------------------------------------------------
# TTY detection
# ---------------------------------------------------------------------------

def get_tty():
    """Get the TTY by walking up the process tree until we find one."""
    try:
        result = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,tty="],
            capture_output=True, text=True, timeout=2,
        )
        pids = {}  # pid -> (ppid, tty)
        for line in result.stdout.strip().splitlines():
            parts = line.split()
            if len(parts) >= 3:
                try:
                    pids[int(parts[0])] = (int(parts[1]), parts[2])
                except ValueError:
                    pass

        current = os.getpid()
        for _ in range(30):
            info = pids.get(current)
            if info is None:
                break
            ppid, tty = info
            if tty and tty not in ("??", "-"):
                return tty if tty.startswith("/dev/") else f"/dev/{tty}"
            current = ppid
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# Terminal detection via process tree
# ---------------------------------------------------------------------------

def get_process_tree():
    """Build pid -> (ppid, command) mapping from ps."""
    try:
        result = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,comm="],
            capture_output=True, text=True, timeout=3,
        )
        tree = {}
        for line in result.stdout.strip().splitlines():
            parts = line.split(None, 2)
            if len(parts) >= 3:
                try:
                    tree[int(parts[0])] = (int(parts[1]), parts[2])
                except ValueError:
                    pass
        return tree
    except Exception:
        return {}


def walk_ancestors(pid, tree, max_depth=30):
    """Yield (pid, command) walking up the process tree."""
    current = pid
    depth = 0
    while current > 1 and depth < max_depth:
        info = tree.get(current)
        if info is None:
            break
        ppid, comm = info
        yield current, comm
        current = ppid
        depth += 1


def detect_terminal(pid=None):
    """Detect terminal type by walking the process tree from Claude's PID.

    Returns one of: "cmux", "tmux", "iterm2", "terminal_app", "unknown".
    Detection order matters — tmux and cmux are checked first because they
    can be nested inside any terminal app.
    """
    if pid is None:
        pid = os.getppid()

    tree = get_process_tree()

    for _, comm in walk_ancestors(pid, tree):
        name = os.path.basename(comm).lower()

        if "cmux" in name:
            return "cmux"
        if name.startswith("tmux"):
            return "tmux"
        if name in ("iterm2", "iterm", "itermserver-main"):
            return "iterm2"
        if name in ("terminal", "terminal.app"):
            return "terminal_app"

    return "unknown"


# ---------------------------------------------------------------------------
# Notification dispatch
# ---------------------------------------------------------------------------

def find_notifier():
    """Find terminal-notifier binary."""
    path = shutil.which("terminal-notifier")
    if path:
        return path
    for p in ("/opt/homebrew/bin/terminal-notifier", "/usr/local/bin/terminal-notifier"):
        if os.path.isfile(p):
            return p
    return None


def send_notification(terminal, tty, pid):
    """Send notification with click-to-focus behavior."""

    # cmux — use native cmux notify, no need for terminal-notifier
    if terminal == "cmux":
        cmux_bin = shutil.which("cmux")
        if cmux_bin:
            subprocess.Popen(
                [cmux_bin, "notify", "Claude Code 需要你的关注"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return
        # cmux binary not found, fall through to terminal-notifier

    notifier = find_notifier()

    # Build the focus command for -execute
    focus_script = os.path.join(FOCUSERS_DIR, f"{terminal}.sh")
    if not os.path.isfile(focus_script):
        focus_script = None

    if notifier and focus_script and tty:
        cmd = [
            notifier,
            "-title", "Claude Code",
            "-message", "Claude Code 需要你的关注",
            "-sound", "Glass",
            "-group", f"claude-notify-{tty}",
            "-execute", f'"{focus_script}" "{tty}" "{pid or ""}"',
        ]
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    elif notifier:
        # No focus script or no TTY — plain notification
        cmd = [
            notifier,
            "-title", "Claude Code",
            "-message", "Claude Code 需要你的关注",
            "-sound", "Glass",
        ]
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    else:
        # Final fallback — osascript
        subprocess.Popen(
            [
                "osascript", "-e",
                'display notification "Claude Code 需要你的关注" '
                'with title "Claude Code" sound name "Glass"',
            ],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    try:
        stdin_data = sys.stdin.read()
        data = json.loads(stdin_data) if stdin_data.strip() else {}
    except (json.JSONDecodeError, ValueError):
        data = {}

    tty = get_tty()
    pid = os.getppid()
    terminal = detect_terminal(pid)

    send_notification(terminal, tty, pid)


if __name__ == "__main__":
    main()
