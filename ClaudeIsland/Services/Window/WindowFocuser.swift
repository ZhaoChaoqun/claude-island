//
//  WindowFocuser.swift
//  ClaudeIsland
//
//  Focuses terminal windows using multiple strategies:
//  1. NSWorkspace (works everywhere, app-level)
//  2. AppleScript/JXA (tab/pane level for supported terminals)
//  3. yabai (window-level for tiling WM users)
//

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "WindowFocuser")

/// Focuses windows using multiple strategies
actor WindowFocuser {
    static let shared = WindowFocuser()

    private init() {}

    // MARK: - Primary API

    /// Focus a terminal window by its bundle ID.
    /// This is the main entry point — works without yabai.
    func focusTerminalApp(bundleId: String) async -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) else {
            logger.debug("No running app with bundle ID: \(bundleId, privacy: .public)")
            return false
        }

        let activated = app.activate()
        if activated {
            logger.info("Activated app: \(bundleId, privacy: .public)")
        } else {
            logger.warning("Failed to activate app: \(bundleId, privacy: .public)")
        }
        return activated
    }

    /// Focus a terminal and try to target the correct tab/pane
    /// Strategy: AppleScript tab targeting → tmux pane switch → app activate fallback
    func focusTerminal(info: TerminalAppInfo, sessionPid: Int?) async -> Bool {
        // Step 1: Try AppleScript tab/pane targeting if supported and we have a PID
        if let pid = sessionPid, info.supportsTabFocus {
            let tabFocused = await focusTabByAppleScript(
                terminalType: info.type,
                bundleId: info.bundleIds.first ?? "",
                claudePid: pid
            )
            if tabFocused {
                return true
            }
        }

        // Step 2: Try tmux pane targeting if we have a PID
        if let pid = sessionPid {
            let tmuxFocused = await focusTmuxPane(claudePid: pid)
            if tmuxFocused {
                // Also activate the terminal app window
                for bundleId in info.bundleIds {
                    if await focusTerminalApp(bundleId: bundleId) {
                        return true
                    }
                }
            }
        }

        // Step 3: Fallback — just activate the app
        for bundleId in info.bundleIds {
            if await focusTerminalApp(bundleId: bundleId) {
                return true
            }
        }

        return false
    }

    // MARK: - yabai (existing)

    /// Focus a window by yabai window ID
    func focusWindow(id: Int) async -> Bool {
        guard let yabaiPath = await WindowFinder.shared.getYabaiPath() else { return false }

        do {
            _ = try await ProcessExecutor.shared.run(yabaiPath, arguments: [
                "-m", "window", "--focus", String(id)
            ])
            return true
        } catch {
            return false
        }
    }

    /// Focus the tmux window for a terminal (yabai path)
    func focusTmuxWindow(terminalPid: Int, windows: [YabaiWindow]) async -> Bool {
        // Try to find actual tmux window
        if let tmuxWindow = WindowFinder.shared.findTmuxWindow(forTerminalPid: terminalPid, windows: windows) {
            return await focusWindow(id: tmuxWindow.id)
        }

        // Fall back to any non-Claude window
        if let window = WindowFinder.shared.findNonClaudeWindow(forTerminalPid: terminalPid, windows: windows) {
            return await focusWindow(id: window.id)
        }

        return false
    }

    // MARK: - tmux pane targeting

    /// Switch to the tmux pane containing a Claude process
    private func focusTmuxPane(claudePid: Int) async -> Bool {
        guard let target = await TmuxController.shared.findTmuxTarget(forClaudePid: claudePid) else {
            return false
        }
        return await TmuxController.shared.switchToPane(target: target)
    }

    // MARK: - AppleScript tab targeting

    /// Focus a specific tab in a terminal app using AppleScript
    private func focusTabByAppleScript(
        terminalType: TerminalType,
        bundleId: String,
        claudePid: Int
    ) async -> Bool {
        switch terminalType {
        case .terminalApp:
            return await focusTerminalAppTab(claudePid: claudePid)
        case .iterm2:
            return await focusITerm2Tab(claudePid: claudePid)
        case .kitty:
            return await focusKittyWindow(claudePid: claudePid)
        default:
            return false
        }
    }

    /// Terminal.app: Find tab containing the Claude process's TTY
    private func focusTerminalAppTab(claudePid: Int) async -> Bool {
        // Find TTY for the Claude process
        guard let tty = findTTY(forPid: claudePid) else {
            logger.debug("No TTY found for pid \(claudePid)")
            return false
        }

        let script = """
        tell application "Terminal"
            activate
            set targetTTY to "\(tty)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is targetTTY then
                        set selected tab of w to t
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """

        return await runAppleScript(script)
    }

    /// iTerm2: Find session containing the Claude process via PID tracking
    private func focusITerm2Tab(claudePid: Int) async -> Bool {
        // iTerm2's AppleScript can iterate sessions and check PIDs
        // We look for a session whose child processes include our Claude PID
        let tty = findTTY(forPid: claudePid)
        guard let ttyName = tty else {
            logger.debug("No TTY found for iTerm2 tab focus, pid \(claudePid)")
            return false
        }

        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(ttyName)" then
                            select t
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """

        return await runAppleScript(script)
    }

    /// Kitty: Use kitten command for window focus
    private func focusKittyWindow(claudePid: Int) async -> Bool {
        // Kitty uses its own remote control protocol
        // `kitty @ focus-window --match pid:<pid>` can focus by PID
        let kittyPaths = ["/opt/homebrew/bin/kitty", "/usr/local/bin/kitty"]
        for kittyPath in kittyPaths {
            guard FileManager.default.isExecutableFile(atPath: kittyPath) else { continue }

            do {
                _ = try await ProcessExecutor.shared.run(kittyPath, arguments: [
                    "@", "focus-window", "--match", "pid:\(claudePid)"
                ])
                return true
            } catch {
                logger.debug("Kitty remote control failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return false
    }

    // MARK: - Helpers

    /// Find TTY for a given PID by walking up the process tree
    private nonisolated func findTTY(forPid pid: Int) -> String? {
        let tree = ProcessTreeBuilder.shared.buildTree()
        var current = pid
        var depth = 0

        while current > 1 && depth < 20 {
            guard let info = tree[current] else { break }
            if let tty = info.tty {
                return "/dev/\(tty)"
            }
            current = info.ppid
            depth += 1
        }

        return nil
    }

    /// Run an AppleScript and return whether it succeeded
    private func runAppleScript(_ source: String) async -> Bool {
        // Use osascript for AppleScript execution
        do {
            let result = await ProcessExecutor.shared.runWithResult(
                "/usr/bin/osascript",
                arguments: ["-e", source]
            )
            switch result {
            case .success(let output):
                let trimmed = output.output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed == "true"
            case .failure(let error):
                logger.debug("AppleScript failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }
}
