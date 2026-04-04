//
//  TerminalResolver.swift
//  ClaudeIsland
//
//  Resolves which terminal application a Claude session is running in.
//  Uses process tree walking + NSWorkspace to identify the terminal app.
//

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "TerminalResolver")

/// Resolved terminal information for a session
struct ResolvedTerminal: Sendable, Equatable {
    /// The terminal application type
    let appInfo: TerminalAppInfo

    /// The running application's bundle ID (verified running)
    let bundleId: String

    /// Whether the session is inside tmux
    let isInTmux: Bool
}

/// Resolves which terminal application owns a Claude session
struct TerminalResolver: Sendable {
    nonisolated static let shared = TerminalResolver()

    private nonisolated init() {}

    /// Resolve terminal for a Claude session by PID
    /// Walks up the process tree to find the terminal app, then verifies it's running
    nonisolated func resolve(claudePid: Int) -> ResolvedTerminal? {
        let tree = ProcessTreeBuilder.shared.buildTree()
        return resolve(claudePid: claudePid, tree: tree)
    }

    /// Resolve terminal using a pre-built process tree (avoids duplicate sysctl calls)
    nonisolated func resolve(claudePid: Int, tree: [Int: ProcessInfo]) -> ResolvedTerminal? {

        // Check if in tmux
        let isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: claudePid, tree: tree)

        // Walk up process tree to find terminal app
        if let appInfo = TerminalAppRegistry.appInfo(forPid: claudePid, tree: tree) {
            // Verify the app is actually running and get its bundle ID
            if let bundleId = findRunningBundleId(for: appInfo) {
                return ResolvedTerminal(
                    appInfo: appInfo,
                    bundleId: bundleId,
                    isInTmux: isInTmux
                )
            }
        }

        // If we're in tmux, the terminal might not be a direct parent.
        // Try to find it via tmux client PID.
        if isInTmux {
            return resolveViaTmuxClient(claudePid: claudePid, tree: tree)
        }

        // Last resort: check running applications against known terminals
        return resolveFromRunningApps()
    }

    /// Resolve terminal using TTY (when PID is not available)
    nonisolated func resolve(tty: String) -> ResolvedTerminal? {
        // Parse TTY to find a PID associated with it
        let tree = ProcessTreeBuilder.shared.buildTree()

        // Find processes on this TTY
        for (pid, info) in tree {
            guard let processTTY = info.tty else { continue }
            if tty.hasSuffix(processTTY) || processTTY == tty {
                // Found a process on this TTY, resolve from here
                if let resolved = resolveFromTree(pid: pid, tree: tree) {
                    return resolved
                }
            }
        }

        return nil
    }

    // MARK: - Private

    /// Walk up from a PID in a pre-built tree
    private nonisolated func resolveFromTree(pid: Int, tree: [Int: ProcessInfo]) -> ResolvedTerminal? {
        let isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: pid, tree: tree)

        if let appInfo = TerminalAppRegistry.appInfo(forPid: pid, tree: tree),
           let bundleId = findRunningBundleId(for: appInfo) {
            return ResolvedTerminal(
                appInfo: appInfo,
                bundleId: bundleId,
                isInTmux: isInTmux
            )
        }

        return nil
    }

    /// Try to find the terminal via tmux client PID
    private nonisolated func resolveViaTmuxClient(claudePid: Int, tree: [Int: ProcessInfo]) -> ResolvedTerminal? {
        // Find tmux server in the parent chain
        var current = claudePid
        var depth = 0
        var tmuxServerPid: Int?

        while current > 1 && depth < 20 {
            guard let info = tree[current] else { break }
            if info.command.lowercased().contains("tmux") {
                tmuxServerPid = current
                break
            }
            current = info.ppid
            depth += 1
        }

        guard let serverPid = tmuxServerPid else { return nil }

        // Find tmux client processes (children of the server, or siblings)
        // tmux clients are separate processes that connect to the server
        for (pid, info) in tree {
            // Look for tmux client processes
            if info.command.lowercased().contains("tmux") && pid != serverPid {
                // Walk up from this client to find the terminal
                if let appInfo = TerminalAppRegistry.appInfo(forPid: pid, tree: tree),
                   let bundleId = findRunningBundleId(for: appInfo) {
                    return ResolvedTerminal(
                        appInfo: appInfo,
                        bundleId: bundleId,
                        isInTmux: true
                    )
                }
            }
        }

        return nil
    }

    /// Fallback: check all running apps for known terminals.
    /// Only returns a result if exactly one terminal app is running,
    /// otherwise we can't determine which terminal owns this session.
    private nonisolated func resolveFromRunningApps() -> ResolvedTerminal? {
        let runningApps = NSWorkspace.shared.runningApplications
        var matches: [(appInfo: TerminalAppInfo, bundleId: String)] = []

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  let appInfo = TerminalAppRegistry.appInfo(forBundleId: bundleId) else {
                continue
            }
            matches.append((appInfo: appInfo, bundleId: bundleId))
        }

        // Only return if exactly one terminal is running — ambiguous otherwise
        guard matches.count == 1, let match = matches.first else {
            return nil
        }

        return ResolvedTerminal(
            appInfo: match.appInfo,
            bundleId: match.bundleId,
            isInTmux: false
        )
    }

    /// Find the bundle ID of a running instance for a terminal app
    private nonisolated func findRunningBundleId(for appInfo: TerminalAppInfo) -> String? {
        let runningApps = NSWorkspace.shared.runningApplications
        for bundleId in appInfo.bundleIds {
            if runningApps.contains(where: { $0.bundleIdentifier == bundleId }) {
                return bundleId
            }
        }
        return nil
    }
}
