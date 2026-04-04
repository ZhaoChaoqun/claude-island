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

    /// Whether this command contains any dangerous patterns
    private var isDangerous: Bool {
        Self.dangerousPatterns.contains { pattern in
            command.localizedCaseInsensitiveContains(pattern)
        }
    }

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
        "> /dev/",
        "shutdown",
        "reboot",
        "kill -9",
        "killall",
        "pkill",
        "format ",
        "fdisk",
    ]

    /// Keywords to highlight in the command
    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi",
        "for", "while", "do", "done",
        "case", "esac", "in",
        "function", "return", "exit",
        "export", "source", "eval",
        "true", "false",
    ]

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
            ForEach(Array(commandLines.enumerated()), id: \.offset) { _, line in
                highlightedLine(line)
            }
        }
    }

    private var commandLines: [String] {
        // Split by && or ; for multi-command display
        command.components(separatedBy: "\n")
    }

    private func highlightedLine(_ line: String) -> some View {
        HStack(spacing: 0) {
            // Prompt symbol
            Text("$")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(TerminalColors.dim)
                .padding(.trailing, 4)

            // Check if this specific line has dangerous content
            let lineDangerous = Self.dangerousPatterns.contains { pattern in
                line.localizedCaseInsensitiveContains(pattern)
            }

            Text(line)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(lineDangerous ? TerminalColors.red : .white.opacity(0.8))
                .lineLimit(nil)
        }
    }
}
