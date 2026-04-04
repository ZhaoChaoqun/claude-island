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

struct ApprovalDiffView: View {
    let filePath: String

    /// Precomputed diff lines (stored, not recomputed on every render)
    let lines: [DiffLine]
    /// Precomputed diff stats
    let stats: DiffStats
    /// Whether this is a Write (full file content) vs Edit (old → new)
    let isWrite: Bool

    init(filePath: String, oldString: String?, newString: String?) {
        self.filePath = filePath
        self.isWrite = (oldString == nil)

        if let old = oldString, let new = newString {
            self.lines = Self.computeEditDiff(old: old, new: new)
        } else if let content = newString {
            self.lines = Self.computeWriteDiff(content: content)
        } else {
            self.lines = []
        }

        let added = self.lines.filter { $0.kind == .added }.count
        let removed = self.lines.filter { $0.kind == .removed }.count
        self.stats = DiffStats(additions: added, deletions: removed)
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

    /// Maximum line count for LCS diff. Beyond this, fall back to simple all-removed/all-added
    /// to avoid O(m×n) memory and CPU cost on large inputs.
    private static let lcsLineThreshold = 200

    /// Compute diff for Edit tool (old_string → new_string) with line-level comparison.
    /// Uses LCS for small inputs; falls back to simple diff for large inputs.
    private static func computeEditDiff(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        // Guard against O(m×n) blowup on large files
        if oldLines.count > lcsLineThreshold || newLines.count > lcsLineThreshold {
            return computeSimpleDiff(oldLines: oldLines, newLines: newLines)
        }

        // Compute LCS table
        let lcs = computeLCS(oldLines, newLines)

        // Walk LCS table to produce diff lines
        var result: [DiffLine] = []
        var lineId = 0
        var i = oldLines.count
        var j = newLines.count
        var stack: [(kind: DiffLine.Kind, text: String, oldNum: Int?, newNum: Int?)] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                // Context line (same in both)
                stack.append((.context, oldLines[i - 1], i, j))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j]) {
                // Added line
                stack.append((.added, newLines[j - 1], nil, j))
                j -= 1
            } else if i > 0 {
                // Removed line
                stack.append((.removed, oldLines[i - 1], i, nil))
                i -= 1
            }
        }

        // Reverse since we walked backwards
        for entry in stack.reversed() {
            result.append(DiffLine(
                id: lineId,
                kind: entry.kind,
                text: entry.text,
                oldLineNumber: entry.oldNum,
                newLineNumber: entry.newNum
            ))
            lineId += 1
        }

        return result
    }

    /// Compute LCS length table for two arrays of strings
    private static func computeLCS(_ a: [String], _ b: [String]) -> [[Int]] {
        let m = a.count
        let n = b.count
        var table = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }

        return table
    }

    /// Simple fallback diff: all old lines removed, all new lines added.
    /// Used when input exceeds the LCS threshold.
    private static func computeSimpleDiff(oldLines: [String], newLines: [String]) -> [DiffLine] {
        var result: [DiffLine] = []
        var lineId = 0

        for (i, line) in oldLines.enumerated() {
            result.append(DiffLine(
                id: lineId, kind: .removed, text: line,
                oldLineNumber: i + 1, newLineNumber: nil
            ))
            lineId += 1
        }
        for (i, line) in newLines.enumerated() {
            result.append(DiffLine(
                id: lineId, kind: .added, text: line,
                oldLineNumber: nil, newLineNumber: i + 1
            ))
            lineId += 1
        }
        return result
    }

    /// Compute diff for Write tool (all lines are additions)
    private static func computeWriteDiff(content: String) -> [DiffLine] {
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
