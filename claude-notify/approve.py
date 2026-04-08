#!/usr/bin/env python3
"""
claude-notify approve — PermissionRequest hook for Claude Code.

Reads the PermissionRequest event from stdin, shows a macOS alert via
`alerter` with Approve/Deny buttons, and returns the user's decision
as JSON on stdout so Claude Code can proceed without terminal interaction.

Requires: alerter (brew install alerter)
If alerter is not installed, exits silently to let Claude Code fall back
to its normal terminal-based permission prompt.
"""
import json
import os
import shutil
import subprocess
import sys

ALERTER_TIMEOUT = 120  # seconds before auto-fallback


def find_alerter():
    """Find alerter binary."""
    path = shutil.which("alerter")
    if path:
        return path
    for p in ("/opt/homebrew/bin/alerter", "/usr/local/bin/alerter"):
        if os.path.isfile(p):
            return p
    return None


def summarize_tool_input(tool_name, tool_input):
    """Build a human-readable summary of the tool call."""
    if tool_name == "Bash":
        cmd = tool_input.get("command", "")
        if len(cmd) > 200:
            cmd = cmd[:200] + "..."
        return cmd
    if tool_name in ("Write", "Edit"):
        return tool_input.get("file_path", "")
    if tool_name == "Read":
        return tool_input.get("file_path", "")
    if tool_name in ("Glob", "Grep"):
        pattern = tool_input.get("pattern", "")
        path = tool_input.get("path", "")
        return f"{pattern} in {path}" if path else pattern
    if tool_name == "WebFetch":
        return tool_input.get("url", "")
    if tool_name == "WebSearch":
        return tool_input.get("query", "")
    if tool_name == "Agent":
        return tool_input.get("prompt", "")[:200]
    # MCP tools or unknown
    return json.dumps(tool_input, ensure_ascii=False)[:200]


def main():
    try:
        stdin_data = sys.stdin.read()
        data = json.loads(stdin_data) if stdin_data.strip() else {}
    except (json.JSONDecodeError, ValueError):
        return

    if data.get("hook_event_name") != "PermissionRequest":
        return

    alerter = find_alerter()
    if not alerter:
        return  # No alerter — fall back to terminal prompt

    tool_name = data.get("tool_name", "Unknown Tool")
    tool_input = data.get("tool_input", {})
    summary = summarize_tool_input(tool_name, tool_input)

    try:
        result = subprocess.run(
            [
                alerter,
                "--title", f"Claude Code — {tool_name}",
                "--message", summary,
                "--close-label", "Deny",
                "--actions", "Approve",
                "--timeout", str(ALERTER_TIMEOUT),
                "--sound", "default",
            ],
            capture_output=True, text=True, timeout=ALERTER_TIMEOUT + 5,
        )
        answer = result.stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        return  # Timeout or error — fall back to terminal prompt

    if answer == "Approve":
        decision = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        }
    elif answer in ("Deny", "@CLOSED"):
        decision = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "deny",
                    "message": "User denied via notification",
                },
            }
        }
    else:
        # @TIMEOUT or unexpected — fall back to terminal prompt
        return

    json.dump(decision, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
