//
//  DiffView.swift
//  ClaudeIsland
//
//  Renders code diffs with red/green line highlighting
//  for Edit (old_string → new_string) and Write (new content) tools.
//

import SwiftUI

/// Parsed diff line with its type
struct DiffLine: Identifiable {
    enum Kind { case context, added, removed }

    let id: Int
    let kind: Kind
    let text: String
    /// Line number in the old file (nil for added lines)
    let oldLineNumber: Int?
    /// Line number in the new file (nil for removed lines)
    let newLineNumber: Int?
}

/// Statistics for a diff
struct DiffStats {
    let additions: Int
    let deletions: Int
}

struct DiffView: View {
    let filePath: String
    let oldString: String?
    let newString: String?

    /// Whether this is a Write (full file content) vs Edit (old → new)
    private var isWrite: Bool { oldString == nil }

    private var lines: [DiffLine] {
        if let old = oldString, let new = newString {
            return computeEditDiff(old: old, new: new)
        } else if let content = newString {
            return computeWriteDiff(content: content)
        }
        return []
    }

    private var stats: DiffStats {
        let added = lines.filter { $0.kind == .added }.count
        let removed = lines.filter { $0.kind == .removed }.count
        return DiffStats(additions: added, deletions: removed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: file path + stats
            header

            // Diff lines
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        diffLineView(line)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            // File icon
            Image(systemName: isWrite ? "doc.badge.plus" : "pencil.line")
                .font(.system(size: 9))
                .foregroundColor(TerminalColors.dim)

            // File path (just filename for compact display)
            Text(fileName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            Spacer()

            // Stats badge
            statsLabel
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
    }

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    @ViewBuilder
    private var statsLabel: some View {
        HStack(spacing: 4) {
            if stats.additions > 0 {
                Text("+\(stats.additions)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalColors.green)
            }
            if stats.deletions > 0 {
                Text("-\(stats.deletions)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalColors.red)
            }
        }
    }

    // MARK: - Line Rendering

    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Gutter (line numbers)
            gutter(line)

            // Prefix (+/-/space)
            Text(linePrefix(line))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(prefixColor(line))
                .frame(width: 12, alignment: .center)

            // Code content
            Text(line.text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(textColor(line))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(backgroundColor(line))
    }

    private func gutter(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            Text(line.oldLineNumber.map { String($0) } ?? "")
                .frame(width: 24, alignment: .trailing)
            Text(line.newLineNumber.map { String($0) } ?? "")
                .frame(width: 24, alignment: .trailing)
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundColor(.white.opacity(0.2))
        .padding(.trailing, 4)
    }

    private func linePrefix(_ line: DiffLine) -> String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private func prefixColor(_ line: DiffLine) -> Color {
        switch line.kind {
        case .added: return TerminalColors.green
        case .removed: return TerminalColors.red
        case .context: return .clear
        }
    }

    private func textColor(_ line: DiffLine) -> Color {
        switch line.kind {
        case .added: return TerminalColors.green.opacity(0.9)
        case .removed: return TerminalColors.red.opacity(0.9)
        case .context: return .white.opacity(0.5)
        }
    }

    private func backgroundColor(_ line: DiffLine) -> Color {
        switch line.kind {
        case .added: return TerminalColors.green.opacity(0.08)
        case .removed: return TerminalColors.red.opacity(0.08)
        case .context: return .clear
        }
    }

    // MARK: - Diff Computation

    /// Compute diff for Edit tool (old_string → new_string)
    private func computeEditDiff(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        var result: [DiffLine] = []
        var lineId = 0

        // Simple diff: show all old lines as removed, all new lines as added
        // For short diffs this is clear enough; a full LCS would be overkill here
        let maxContext = 0 // No context lines for simple replacement

        for (i, line) in oldLines.enumerated() {
            result.append(DiffLine(
                id: lineId,
                kind: .removed,
                text: line,
                oldLineNumber: i + 1,
                newLineNumber: nil
            ))
            lineId += 1
        }

        for (i, line) in newLines.enumerated() {
            result.append(DiffLine(
                id: lineId,
                kind: .added,
                text: line,
                oldLineNumber: nil,
                newLineNumber: i + 1
            ))
            lineId += 1
        }

        return result
    }

    /// Compute diff for Write tool (all lines are additions)
    private func computeWriteDiff(content: String) -> [DiffLine] {
        let lines = content.components(separatedBy: "\n")
        return lines.enumerated().map { (i, line) in
            DiffLine(
                id: i,
                kind: .added,
                text: line,
                oldLineNumber: nil,
                newLineNumber: i + 1
            )
        }
    }
}
