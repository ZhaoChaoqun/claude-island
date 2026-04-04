//
//  CommandHighlightView.swift
//  ClaudeIsland
//
//  Renders Bash commands with syntax highlighting.
//  Dangerous commands (rm -rf, sudo, etc.) are highlighted in red.
//

import SwiftUI

struct CommandHighlightView: View {
    let command: String

    /// Cached dangerous flag — computed once at init, not per render
    let isDangerous: Bool

    /// Dangerous command patterns that warrant a red warning
    private static let dangerousPatterns: [String] = [
        "rm -rf",
        "rm -r /",
        "rm -f /",
        "sudo ",
        "chmod 777",
        "chmod -R 777",
        "mkfs",
        "dd if=",
        ":> /",
        "shutdown",
        "reboot",
        "kill -9",
        "killall",
        "pkill",
        "format ",
        "fdisk",
    ]

    /// Safe /dev/ directory prefixes — these are virtual/pseudo filesystems, not block devices.
    /// Matches exact name (e.g. "fd") or subdirectory path (e.g. "fd/3").
    private static let safeDevPrefixes = ["pts", "fd", "shm"]

    /// Safe /dev/ targets that should NOT trigger the dangerous redirect warning.
    /// Anything redirected to /dev/ that isn't in this list is flagged.
    private static let safeDevTargets: Set<String> = [
        "null", "zero", "random", "urandom",
        "stdin", "stdout", "stderr",
        "tty", "console", "full",
    ]

    /// Redirect patterns to /dev/ — covers both `> /dev/` (with space) and `>/dev/` (no space)
    private static let devRedirectPatterns = ["> /dev/", ">/dev/"]

    /// Check if a line contains a dangerous redirect to /dev/ (block devices, etc.)
    /// Matches `> /dev/X` and `>/dev/X` but excludes known-safe targets like /dev/null, /dev/zero.
    private static func hasDangerousDevRedirect(_ line: String) -> Bool {
        let lowered = line.lowercased()
        for pattern in devRedirectPatterns {
            var searchRange = lowered.startIndex..<lowered.endIndex
            while let range = lowered.range(of: pattern, range: searchRange) {
                let afterPrefix = range.upperBound
                guard afterPrefix < lowered.endIndex else {
                    // "> /dev/" at end of line — suspicious, flag it
                    return true
                }
                // Extract the device name (chars until whitespace, quote, or end)
                let rest = lowered[afterPrefix...]
                let deviceName = String(rest.prefix(while: { !$0.isWhitespace && $0 != "\"" && $0 != "'" && $0 != ";" && $0 != "|" && $0 != "&" }))
                // Check safe directory prefixes (pts, fd, shm) — exact name or subdirectory
                let isSafePrefix = safeDevPrefixes.contains { prefix in
                    deviceName == prefix || deviceName.hasPrefix("\(prefix)/")
                }
                if isSafePrefix {
                    // safe — skip
                } else if safeDevTargets.contains(deviceName) {
                    // safe — skip
                } else {
                    return true
                }
                searchRange = range.upperBound..<lowered.endIndex
            }
        }
        return false
    }

    /// Per-line danger cache: true if that line contains a dangerous pattern
    private let lineDangerFlags: [Bool]

    init(command: String) {
        self.command = command

        let lines = command.components(separatedBy: "\n")
        let flags = lines.map { line in
            let matchesPattern = Self.dangerousPatterns.contains { pattern in
                line.range(of: pattern, options: .caseInsensitive) != nil
            }
            return matchesPattern || Self.hasDangerousDevRedirect(line)
        }
        self.lineDangerFlags = flags
        self.isDangerous = flags.contains(true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header

            // Command content
            ScrollView(.horizontal, showsIndicators: false) {
                commandText
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .frame(maxHeight: 80)
        }
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 9))
                .foregroundColor(TerminalColors.dim)

            Text("Bash")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            if isDangerous {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    Text("Dangerous")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(TerminalColors.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isDangerous ? TerminalColors.red.opacity(0.06) : Color.white.opacity(0.04))
    }

    // MARK: - Command Rendering

    private var commandText: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(zip(commandLines.indices, commandLines)), id: \.0) { index, line in
                highlightedLine(line, isDangerousLine: lineDangerFlags[index], isFirstLine: index == 0)
            }
        }
    }

    private var commandLines: [String] {
        command.components(separatedBy: "\n")
    }

    private func highlightedLine(_ line: String, isDangerousLine: Bool, isFirstLine: Bool) -> some View {
        HStack(spacing: 0) {
            // Prompt symbol: $ for first line, > for continuation lines
            Text(isFirstLine ? "$" : ">")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(TerminalColors.dim)
                .padding(.trailing, 4)

            // Code content — red if dangerous, normal otherwise
            Text(line)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isDangerousLine ? TerminalColors.red : .white.opacity(0.8))
                .lineLimit(nil)
        }
    }
}
