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

    /// Cached TTY device path (e.g. "/dev/ttys003") to avoid rebuilding the process tree on each jump
    let tty: String?
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
        // Fetch running apps once for the entire resolve chain (single DispatchQueue.main.sync)
        let apps = Self.getRunningApps()

        // Check if in tmux
        let isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: claudePid, tree: tree)

        // Find TTY from the tree (cache it so we don't rebuild on each jump)
        let tty = findTTY(forPid: claudePid, tree: tree)

        // Walk up process tree to find terminal app
        if let appInfo = TerminalAppRegistry.appInfo(forPid: claudePid, tree: tree) {
            // Verify the app is actually running and get its bundle ID
            if let bundleId = findRunningBundleId(for: appInfo, apps: apps) {
                return ResolvedTerminal(
                    appInfo: appInfo,
                    bundleId: bundleId,
                    isInTmux: isInTmux,
                    tty: tty
                )
            }
        }

        // If we're in tmux, the terminal might not be a direct parent.
        // Try to find it via tmux client PID.
        if isInTmux {
            return resolveViaTmuxClient(claudePid: claudePid, tree: tree, tty: tty, apps: apps)
        }

        // Last resort: check running applications against known terminals
        return resolveFromRunningApps(tty: tty, apps: apps)
    }

    /// Resolve terminal using TTY (when PID is not available)
    nonisolated func resolve(tty: String) -> ResolvedTerminal? {
        // Parse TTY to find a PID associated with it
        let tree = ProcessTreeBuilder.shared.buildTree()
        let apps = Self.getRunningApps()

        // Find processes on this TTY
        for (pid, info) in tree {
            guard let processTTY = info.tty else { continue }
            if tty.hasSuffix(processTTY) || processTTY == tty {
                // Found a process on this TTY, resolve from here
                if let resolved = resolveFromTree(pid: pid, tree: tree, apps: apps) {
                    return resolved
                }
            }
        }

        return nil
    }

    // MARK: - Private

    /// Walk up from a PID in a pre-built tree
    private nonisolated func resolveFromTree(pid: Int, tree: [Int: ProcessInfo], apps: [NSRunningApplication]) -> ResolvedTerminal? {
        let isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: pid, tree: tree)
        let tty = findTTY(forPid: pid, tree: tree)

        if let appInfo = TerminalAppRegistry.appInfo(forPid: pid, tree: tree),
           let bundleId = findRunningBundleId(for: appInfo, apps: apps) {
            return ResolvedTerminal(
                appInfo: appInfo,
                bundleId: bundleId,
                isInTmux: isInTmux,
                tty: tty
            )
        }

        return nil
    }

    /// Try to find the terminal via tmux client PID
    private nonisolated func resolveViaTmuxClient(claudePid: Int, tree: [Int: ProcessInfo], tty: String?, apps: [NSRunningApplication]) -> ResolvedTerminal? {
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

        // Find tmux client processes that belong to THIS server.
        // tmux clients are spawned by the server, so ppid should match serverPid.
        for (pid, info) in tree {
            guard pid != serverPid,
                  info.ppid == serverPid,
                  info.command.lowercased().hasPrefix("tmux") else { continue }

            // Walk up from this client to find the terminal
            if let appInfo = TerminalAppRegistry.appInfo(forPid: pid, tree: tree),
               let bundleId = findRunningBundleId(for: appInfo, apps: apps) {
                return ResolvedTerminal(
                    appInfo: appInfo,
                    bundleId: bundleId,
                    isInTmux: true,
                    tty: tty
                )
            }
        }

        return nil
    }

    /// Fallback: check all running apps for known terminals.
    /// Only returns a result if exactly one terminal app is running,
    /// otherwise we can't determine which terminal owns this session.
    private nonisolated func resolveFromRunningApps(tty: String? = nil, apps: [NSRunningApplication]) -> ResolvedTerminal? {
        var matches: [(appInfo: TerminalAppInfo, bundleId: String)] = []

        for app in apps {
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
            isInTmux: false,
            tty: tty
        )
    }

    /// Find the bundle ID of a running instance for a terminal app
    private nonisolated func findRunningBundleId(for appInfo: TerminalAppInfo, apps: [NSRunningApplication]) -> String? {
        for bundleId in appInfo.bundleIds {
            if apps.contains(where: { $0.bundleIdentifier == bundleId }) {
                return bundleId
            }
        }
        return nil
    }

    /// Access NSWorkspace.shared.runningApplications safely from the main thread.
    /// NSWorkspace APIs should be called on the main thread.
    private nonisolated static func getRunningApps() -> [NSRunningApplication] {
        if Thread.isMainThread {
            return NSWorkspace.shared.runningApplications
        }
        return DispatchQueue.main.sync {
            NSWorkspace.shared.runningApplications
        }
    }

    /// Find TTY for a given PID by walking up a pre-built process tree
    private nonisolated func findTTY(forPid pid: Int, tree: [Int: ProcessInfo]) -> String? {
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
}
