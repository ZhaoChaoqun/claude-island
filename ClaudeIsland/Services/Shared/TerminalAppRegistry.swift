//
//  TerminalAppRegistry.swift
//  ClaudeIsland
//
//  Centralized registry of known terminal applications with metadata
//  for identification, display, and window focusing capabilities.
//

import Foundation

// MARK: - Terminal App Definition

/// A known terminal application with its metadata
struct TerminalAppInfo: Sendable, Equatable {
    /// Unique identifier for this terminal type
    let type: TerminalType

    /// macOS bundle identifier(s) — some apps have multiple
    let bundleIds: [String]

    /// Process name patterns for matching in process tree
    let processNames: [String]

    /// SF Symbol name for display
    let iconName: String

    /// Human-readable display name
    let displayName: String

    /// Whether the terminal supports AppleScript/JXA tab targeting
    let supportsTabFocus: Bool

    /// Whether the terminal supports pane-level targeting
    let supportsPaneFocus: Bool
}

/// Known terminal types
enum TerminalType: String, Sendable, CaseIterable, Equatable {
    case terminalApp = "terminal"
    case iterm2 = "iterm2"
    case ghostty = "ghostty"
    case warp = "warp"
    case alacritty = "alacritty"
    case kitty = "kitty"
    case hyper = "hyper"
    case wezterm = "wezterm"
    case tabby = "tabby"
    case rio = "rio"
    case vscode = "vscode"
    case vscodeInsiders = "vscode-insiders"
    case cursor = "cursor"
    case windsurf = "windsurf"
    case zed = "zed"
    case unknown = "unknown"
}

// MARK: - Terminal App Registry

/// Registry of known terminal application names and bundle identifiers
struct TerminalAppRegistry: Sendable {

    /// All known terminal apps with their metadata
    static let knownApps: [TerminalAppInfo] = [
        // Native terminals
        TerminalAppInfo(
            type: .terminalApp,
            bundleIds: ["com.apple.Terminal"],
            processNames: ["Terminal"],
            iconName: "terminal",
            displayName: "Terminal",
            supportsTabFocus: true,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .iterm2,
            bundleIds: ["com.googlecode.iterm2"],
            processNames: ["iTerm2", "iTerm", "iTermServer-main"],
            iconName: "terminal",
            displayName: "iTerm2",
            supportsTabFocus: true,
            supportsPaneFocus: true
        ),
        TerminalAppInfo(
            type: .ghostty,
            bundleIds: ["com.mitchellh.ghostty"],
            processNames: ["Ghostty", "ghostty"],
            iconName: "terminal",
            displayName: "Ghostty",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .warp,
            bundleIds: ["dev.warp.Warp-Stable"],
            processNames: ["Warp"],
            iconName: "terminal",
            displayName: "Warp",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .alacritty,
            bundleIds: ["io.alacritty", "org.alacritty"],
            processNames: ["Alacritty", "alacritty"],
            iconName: "terminal",
            displayName: "Alacritty",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .kitty,
            bundleIds: ["net.kovidgoyal.kitty"],
            processNames: ["kitty"],
            iconName: "terminal",
            displayName: "Kitty",
            supportsTabFocus: true,
            supportsPaneFocus: true
        ),
        TerminalAppInfo(
            type: .hyper,
            bundleIds: ["co.zeit.hyper"],
            processNames: ["Hyper"],
            iconName: "terminal",
            displayName: "Hyper",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .wezterm,
            bundleIds: ["com.github.wez.wezterm"],
            processNames: ["WezTerm", "wezterm-gui"],
            iconName: "terminal",
            displayName: "WezTerm",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .tabby,
            bundleIds: ["org.tabby"],
            processNames: ["Tabby"],
            iconName: "terminal",
            displayName: "Tabby",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .rio,
            bundleIds: ["com.raphaelamorim.rio"],
            processNames: ["Rio", "rio"],
            iconName: "terminal",
            displayName: "Rio",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),

        // IDE integrated terminals
        TerminalAppInfo(
            type: .vscode,
            bundleIds: ["com.microsoft.VSCode"],
            processNames: ["Code", "Electron"],
            iconName: "chevron.left.forwardslash.chevron.right",
            displayName: "VS Code",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .vscodeInsiders,
            bundleIds: ["com.microsoft.VSCodeInsiders"],
            processNames: ["Code - Insiders"],
            iconName: "chevron.left.forwardslash.chevron.right",
            displayName: "VS Code Insiders",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .cursor,
            bundleIds: ["com.todesktop.230313mzl4w4u92"],
            processNames: ["Cursor"],
            iconName: "cursorarrow.rays",
            displayName: "Cursor",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .windsurf,
            bundleIds: ["com.exafunction.windsurf"],
            processNames: ["Windsurf"],
            iconName: "chevron.left.forwardslash.chevron.right",
            displayName: "Windsurf",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
        TerminalAppInfo(
            type: .zed,
            bundleIds: ["dev.zed.Zed"],
            processNames: ["zed", "Zed"],
            iconName: "chevron.left.forwardslash.chevron.right",
            displayName: "Zed",
            supportsTabFocus: false,
            supportsPaneFocus: false
        ),
    ]

    // MARK: - Lookup Tables (computed once)

    /// All bundle identifiers, flattened
    static let bundleIdentifiers: Set<String> = {
        Set(knownApps.flatMap { $0.bundleIds })
    }()

    /// All process names for matching
    static let appNames: Set<String> = {
        Set(knownApps.flatMap { $0.processNames })
    }()

    /// Bundle ID -> TerminalAppInfo lookup
    private static let bundleIdMap: [String: TerminalAppInfo] = {
        var map: [String: TerminalAppInfo] = [:]
        for app in knownApps {
            for bundleId in app.bundleIds {
                map[bundleId] = app
            }
        }
        return map
    }()

    /// Process name (lowercased) -> TerminalAppInfo lookup
    private static let processNameMap: [String: TerminalAppInfo] = {
        var map: [String: TerminalAppInfo] = [:]
        for app in knownApps {
            for name in app.processNames {
                map[name.lowercased()] = app
            }
        }
        return map
    }()

    // MARK: - Identification

    /// Check if an app name or command path is a known terminal
    static func isTerminal(_ appNameOrCommand: String) -> Bool {
        let lower = appNameOrCommand.lowercased()

        // Check if any known app name is contained in the command (case-insensitive)
        for name in appNames {
            if lower.contains(name.lowercased()) {
                return true
            }
        }

        // Additional checks for common patterns
        return lower.contains("terminal") || lower.contains("iterm")
    }

    /// Check if a bundle identifier is a known terminal
    static func isTerminalBundle(_ bundleId: String) -> Bool {
        bundleIdentifiers.contains(bundleId)
    }

    /// Identify terminal app from bundle ID
    static func appInfo(forBundleId bundleId: String) -> TerminalAppInfo? {
        bundleIdMap[bundleId]
    }

    /// Identify terminal app from a process command string
    static func appInfo(forProcess command: String) -> TerminalAppInfo? {
        let lower = command.lowercased()

        // Direct match on process name
        if let app = processNameMap[lower] {
            return app
        }

        // Check if the command contains a known process name
        // Walk the list in order so more specific matches win first
        for app in knownApps {
            for name in app.processNames {
                if lower.contains(name.lowercased()) {
                    return app
                }
            }
        }

        return nil
    }

    /// Identify terminal app from a process tree by walking up from PID
    static func appInfo(forPid pid: Int, tree: [Int: ProcessInfo]) -> TerminalAppInfo? {
        var current = pid
        var depth = 0

        while current > 1 && depth < 20 {
            guard let info = tree[current] else { break }

            if let app = appInfo(forProcess: info.command) {
                return app
            }

            current = info.ppid
            depth += 1
        }

        return nil
    }
}
