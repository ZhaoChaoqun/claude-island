#!/usr/bin/env python3
"""
claude-notify question — PreToolUse hook for AskUserQuestion.

When Claude asks the user a question via AskUserQuestion, this hook
shows a macOS alert via `alerter` with the question and option buttons.
The user's selection is returned as JSON on stdout so Claude Code can
proceed without terminal interaction.

Constraints:
- Single question only (multiple questions fall back to terminal)
- Up to 3 options (more than 3 fall back to terminal)
- Requires alerter (brew install alerter)

If any constraint is not met, exits silently to let Claude Code show
the normal terminal-based question UI.
"""
import json
import os
import shutil
import subprocess
import sys

ALERTER_TIMEOUT = 120
MAX_OPTIONS = 3
MAX_LABEL_LEN = 40


def find_alerter():
    """Find alerter binary."""
    path = shutil.which("alerter")
    if path:
        return path
    for p in ("/opt/homebrew/bin/alerter", "/usr/local/bin/alerter"):
        if os.path.isfile(p):
            return p
    return None


def truncate(text, max_len):
    """Truncate text with ellipsis if too long."""
    if len(text) <= max_len:
        return text
    return text[: max_len - 3] + "..."


def main():
    try:
        stdin_data = sys.stdin.read()
        data = json.loads(stdin_data) if stdin_data.strip() else {}
    except (json.JSONDecodeError, ValueError):
        return

    if data.get("hook_event_name") != "PreToolUse":
        return
    if data.get("tool_name") != "AskUserQuestion":
        return

    tool_input = data.get("tool_input", {})
    questions = tool_input.get("questions", [])

    # Only handle single question with <= MAX_OPTIONS options
    if len(questions) != 1:
        return
    question = questions[0]
    options = question.get("options", [])
    if not options or len(options) > MAX_OPTIONS:
        return

    # Labels with commas would be split by alerter's --actions parser
    raw_labels = [opt.get("label", "") for opt in options]
    if any("," in label for label in raw_labels):
        return

    alerter = find_alerter()
    if not alerter:
        return

    question_text = question.get("question", "")
    header = question.get("header", "")
    title = f"Claude Code — {header}" if header else "Claude Code"

    # Build alerter command — all options go in --actions,
    # close button is "Skip" (falls back to terminal on click)
    labels = [truncate(opt.get("label", ""), MAX_LABEL_LEN) for opt in options]

    cmd = [
        alerter,
        "--title", title,
        "--message", question_text,
        "--closeLabel", "Skip",
        "--actions", ",".join(labels),
        "--timeout", str(ALERTER_TIMEOUT),
        "--sound", "default",
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=ALERTER_TIMEOUT + 5,
        )
        answer = result.stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        return

    # Map alerter output to the original (untruncated) option label
    selected = None
    for i, label in enumerate(labels):
        if answer == label:
            selected = options[i].get("label", "")
            break

    if selected is None:
        # @CLOSED, @TIMEOUT, Skip, or unexpected — fall back to terminal
        return

    updated_input = dict(tool_input)
    updated_input["answers"] = {question_text: selected}

    decision = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": updated_input,
        }
    }
    json.dump(decision, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
