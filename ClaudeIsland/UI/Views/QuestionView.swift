//
//  QuestionView.swift
//  ClaudeIsland
//
//  Inline question panel for AskUserQuestion tool.
//  Displays question text, clickable option buttons, and optional free-text input.
//  Supports keyboard shortcuts Cmd+1/2/3/4 for quick selection.
//

import SwiftUI

struct QuestionView: View {
    let question: QuestionContext
    let onAnswer: ([String: String]) -> Void

    @State private var selectedOptions: [String: Set<String>] = [:]
    @State private var freeTextInput: String = ""
    @State private var showFreeText: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(question.questions.enumerated()), id: \.offset) { index, item in
                questionItemView(item: item, index: index)
            }

            // Submit button for multi-select or free text
            if needsSubmitButton {
                HStack {
                    Spacer()
                    Button {
                        submitAnswers()
                    } label: {
                        Text("Submit")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        // Keyboard shortcuts for quick option selection (Cmd+1 through Cmd+4)
        .background(
            Group {
                Button("") { selectOptionByIndex(0) }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("") { selectOptionByIndex(1) }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                Button("") { selectOptionByIndex(2) }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                Button("") { selectOptionByIndex(3) }
                    .keyboardShortcut("4", modifiers: .command)
                    .hidden()
            }
        )
    }

    // MARK: - Question Item View

    @ViewBuilder
    private func questionItemView(item: QuestionItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Question header + text
            if let header = item.header, !header.isEmpty {
                Text(header)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(TerminalColors.amber.opacity(0.7))
                    .textCase(.uppercase)
            }

            Text(item.question)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            // Option buttons
            if !item.options.isEmpty {
                optionsGrid(item: item, questionIndex: index)
            }

            // Free text input (shown when "Other" is selected or no options)
            if showFreeText || item.options.isEmpty {
                freeTextInputField(item: item)
            }
        }
    }

    // MARK: - Options Grid

    @ViewBuilder
    private func optionsGrid(item: QuestionItem, questionIndex: Int) -> some View {
        let columns = item.options.count <= 3
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(item.options.enumerated()), id: \.offset) { optionIndex, option in
                optionButton(
                    option: option,
                    questionText: item.question,
                    isMultiSelect: item.multiSelect,
                    shortcutIndex: optionIndex
                )
            }

            // "Other" option for free text
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFreeText.toggle()
                    if showFreeText {
                        isTextFieldFocused = true
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                    Text("Other")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(showFreeText ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(showFreeText ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Option Button

    @ViewBuilder
    private func optionButton(option: QuestionOption, questionText: String, isMultiSelect: Bool, shortcutIndex: Int) -> some View {
        let isSelected = selectedOptions[questionText]?.contains(option.label) ?? false

        Button {
            if isMultiSelect {
                toggleOption(questionText: questionText, label: option.label)
            } else {
                // Single select: immediately submit
                onAnswer([questionText: option.label])
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isMultiSelect {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                    }

                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))

                    Spacer()

                    // Keyboard shortcut hint
                    if shortcutIndex < 4 {
                        Text("\u{2318}\(shortcutIndex + 1)")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                if let desc = option.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(2)
                }
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.clear : Color.white.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Free Text Input

    @ViewBuilder
    private func freeTextInputField(item: QuestionItem) -> some View {
        HStack(spacing: 8) {
            TextField("Type your answer...", text: $freeTextInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .focused($isTextFieldFocused)
                .onSubmit {
                    if !freeTextInput.trimmingCharacters(in: .whitespaces).isEmpty {
                        onAnswer([item.question: freeTextInput])
                    }
                }

            if !freeTextInput.isEmpty {
                Button {
                    onAnswer([item.question: freeTextInput])
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var needsSubmitButton: Bool {
        question.questions.contains { $0.multiSelect }
    }

    private func toggleOption(questionText: String, label: String) {
        if selectedOptions[questionText] == nil {
            selectedOptions[questionText] = []
        }
        if selectedOptions[questionText]!.contains(label) {
            selectedOptions[questionText]!.remove(label)
        } else {
            selectedOptions[questionText]!.insert(label)
        }
    }

    private func selectOptionByIndex(_ index: Int) {
        guard let firstQuestion = question.questions.first,
              index < firstQuestion.options.count else { return }

        let option = firstQuestion.options[index]

        if firstQuestion.multiSelect {
            toggleOption(questionText: firstQuestion.question, label: option.label)
        } else {
            // Single select: immediately submit
            onAnswer([firstQuestion.question: option.label])
        }
    }

    private func submitAnswers() {
        var answers: [String: String] = [:]

        for item in question.questions {
            if let selected = selectedOptions[item.question], !selected.isEmpty {
                // Join multi-select with comma
                answers[item.question] = selected.joined(separator: ", ")
            } else if !freeTextInput.trimmingCharacters(in: .whitespaces).isEmpty {
                answers[item.question] = freeTextInput
            }
        }

        if !answers.isEmpty {
            onAnswer(answers)
        }
    }
}
