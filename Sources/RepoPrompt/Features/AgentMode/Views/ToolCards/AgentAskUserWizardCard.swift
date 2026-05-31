import SwiftUI

/// Structured multi-question ask_user card shared by Agent Mode and Context Builder.
/// Presents one question at a time while keeping all draft state in the owning view model.
struct AgentAskUserWizardCard: View {
    let pending: AgentAskUserPendingState
    let onDraftChange: (_ questionID: String, _ draft: AgentAskUserDraft) -> Void
    let onQuestionIndexChange: (_ index: Int) -> Void
    let onSubmit: () -> Void
    let onSkipAll: () -> Void
    let onUserActivity: () -> Void

    @State private var lastActivitySignalAt: Date?
    @State private var activityWorkGate = WorkItemGate()
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            if let context = nonEmpty(pending.interaction.context) {
                contextBlock(context)
            }

            questionPager

            if let question = currentQuestion {
                questionSection(question)
            }

            actionButtons
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .onChange(of: pending.id) { _, _ in
            cancelPendingActivitySignal()
            lastActivitySignalAt = nil
        }
        .onChange(of: pending.currentQuestionIndex) { _, _ in
            noteUserActivity()
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue != nil {
                noteUserActivity()
            }
        }
        .onDisappear {
            cancelPendingActivitySignal()
        }
    }

    private var currentQuestion: AgentAskUserQuestion? {
        pending.currentQuestion
    }

    private var currentDraft: AgentAskUserDraft {
        guard let question = currentQuestion else { return AgentAskUserDraft() }
        return pending.draftsByQuestionID[question.id] ?? AgentAskUserDraft()
    }

    private var questionCount: Int {
        pending.interaction.questions.count
    }

    private var canGoPrevious: Bool {
        pending.currentQuestionIndex > 0
    }

    private var canGoNext: Bool {
        pending.currentQuestionIndex < max(0, questionCount - 1)
    }

    private var submitButtonLabel: String {
        questionCount > 1 ? "Submit Answers" : "Submit"
    }

    private var headerTitle: String {
        nonEmpty(pending.interaction.title) ?? (questionCount > 1 ? "Agent Questions" : "Agent Question")
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.headline)
                Text("Waiting for your response…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if questionCount > 1 {
                    Text("Question \(pending.currentQuestionIndex + 1) of \(questionCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            let countdownAnchor = pending.timeoutStartedAt ?? pending.interaction.askedAt
            TimeoutCountdownView(startedAt: countdownAnchor, timeoutSeconds: pending.interaction.timeoutSeconds)
                .id(countdownAnchor)
        }
    }

    @ViewBuilder
    private var questionPager: some View {
        if questionCount > 1 {
            HStack(spacing: 8) {
                Button {
                    goToQuestion(pending.currentQuestionIndex - 1)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canGoPrevious)

                Spacer()

                questionProgressDots

                Spacer()

                Button {
                    goToQuestion(pending.currentQuestionIndex + 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canGoNext)
            }
        }
    }

    private var questionProgressDots: some View {
        HStack(spacing: 5) {
            ForEach(Array(pending.interaction.questions.enumerated()), id: \.element.id) { index, question in
                Button {
                    goToQuestion(index)
                } label: {
                    Circle()
                        .fill(progressColor(for: question, at: index))
                        .frame(width: 7, height: 7)
                }
                .buttonStyle(.plain)
                .help("Question \(index + 1)")
            }
        }
    }

    private func progressColor(for question: AgentAskUserQuestion, at index: Int) -> Color {
        if index == pending.currentQuestionIndex { return .blue }
        let draft = pending.draftsByQuestionID[question.id] ?? AgentAskUserDraft()
        if draft.skipped { return .secondary.opacity(0.7) }
        if draft.hasContent { return .green }
        return .secondary.opacity(0.25)
    }

    private func questionSection(_ question: AgentAskUserQuestion) -> some View {
        let draft = pending.draftsByQuestionID[question.id] ?? AgentAskUserDraft()
        return VStack(alignment: .leading, spacing: 12) {
            if let header = nonEmpty(question.header) {
                Text(header)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Text(question.question)
                .font(.body)
                .fontWeight(.medium)
                .textSelection(.enabled)

            if let context = nonEmpty(question.context) {
                contextBlock(context)
            }

            if !question.options.isEmpty {
                optionsSection(question: question, draft: draft)
            }

            if question.allowsCustom {
                customResponseField(question: question, draft: draft)
            }

            skipQuestionToggle(question: question, draft: draft)
        }
        .padding(12)
        .background(Color.white.opacity(0.35))
        .cornerRadius(8)
    }

    private func contextBlock(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(6)
    }

    private func optionsSection(question: AgentAskUserQuestion, draft: AgentAskUserDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: question.allowsMultiple ? "checklist" : "list.bullet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(question.allowsMultiple ? "Select all that apply" : "Select one option")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if draft.skipped {
                    Text("Skipped")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(question.options, id: \.label) { option in
                optionButton(option: option, question: question, draft: draft)
            }
        }
    }

    private func optionButton(option: AgentAskUserOption, question: AgentAskUserQuestion, draft: AgentAskUserDraft) -> some View {
        let isSelected = draft.selectedOptionLabels.contains(option.label)
        return Button {
            toggleOption(option.label, for: question, draft: draft)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: isSelected
                        ? (question.allowsMultiple ? "checkmark.square.fill" : "largecircle.fill.circle")
                        : (question.allowsMultiple ? "square" : "circle")
                )
                .font(.callout)
                .foregroundColor(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.callout)
                        .foregroundColor(.primary)
                    if let description = nonEmpty(option.description) {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.blue.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(draft.skipped)
        .focusable()
        .focused($focusedField, equals: .option(question.id, option.label))
        .onKeyPress(.space) {
            toggleOption(option.label, for: question, draft: draft)
            return .handled
        }
        .focusEffectDisabled()
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(focusedField == .option(question.id, option.label) ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func customResponseField(question: AgentAskUserQuestion, draft: AgentAskUserDraft) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(question.options.isEmpty ? "Response" : "Custom response")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Type your response…", text: customResponseBinding(for: question), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 5)
                .disabled(draft.skipped)
                .focused($focusedField, equals: .custom(question.id))
                .onSubmit {
                    if pending.isComplete {
                        onSubmit()
                    }
                }
        }
    }

    private func skipQuestionToggle(question: AgentAskUserQuestion, draft: AgentAskUserDraft) -> some View {
        Button {
            var updated = draft
            updated.skipped.toggle()
            if updated.skipped {
                updated.selectedOptionLabels = []
                updated.customResponse = ""
            }
            emitDraft(updated, for: question)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: draft.skipped ? "checkmark.circle.fill" : "circle")
                Text(draft.skipped ? "Question skipped" : "Skip this question")
            }
            .font(.caption)
            .foregroundColor(draft.skipped ? .secondary : .blue)
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onSkipAll) {
                Label("Skip All", systemImage: "forward.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            if canGoNext {
                Button("Next") {
                    goToQuestion(pending.currentQuestionIndex + 1)
                }
                .buttonStyle(.bordered)
            }

            Button(action: onSubmit) {
                Label(submitButtonLabel, systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!pending.isComplete)
            .keyboardShortcut(.return, modifiers: .shift)
        }
    }

    private func customResponseBinding(for question: AgentAskUserQuestion) -> Binding<String> {
        Binding(
            get: {
                (pending.draftsByQuestionID[question.id] ?? AgentAskUserDraft()).customResponse
            },
            set: { value in
                var draft = pending.draftsByQuestionID[question.id] ?? AgentAskUserDraft()
                draft.customResponse = value
                draft.skipped = false
                if !question.allowsMultiple, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft.selectedOptionLabels = []
                }
                emitDraft(draft, for: question)
            }
        )
    }

    private func toggleOption(_ label: String, for question: AgentAskUserQuestion, draft: AgentAskUserDraft) {
        guard !draft.skipped else { return }
        var updated = draft
        if question.allowsMultiple {
            if updated.selectedOptionLabels.contains(label) {
                updated.selectedOptionLabels.removeAll { $0 == label }
            } else {
                updated.selectedOptionLabels.append(label)
            }
        } else {
            if updated.selectedOptionLabels.contains(label) {
                updated.selectedOptionLabels = []
            } else {
                updated.selectedOptionLabels = [label]
            }
            updated.customResponse = ""
        }
        updated.skipped = false
        emitDraft(updated, for: question)
    }

    private func emitDraft(_ draft: AgentAskUserDraft, for question: AgentAskUserQuestion) {
        onDraftChange(question.id, draft)
        noteUserActivity()
    }

    private func goToQuestion(_ index: Int) {
        guard pending.interaction.questions.indices.contains(index) else { return }
        onQuestionIndexChange(index)
        noteUserActivity()
    }

    private var activitySignalInterval: TimeInterval {
        max(0.05, min(1.0, pending.interaction.timeoutSeconds / 3.0))
    }

    private func noteUserActivity() {
        let now = Date()
        let interval = activitySignalInterval
        if let lastActivitySignalAt {
            let elapsed = now.timeIntervalSince(lastActivitySignalAt)
            guard elapsed < interval else {
                cancelPendingActivitySignal()
                emitActivitySignal(at: now)
                return
            }

            activityWorkGate.schedule(after: interval - elapsed) {
                emitActivitySignal(at: Date())
            }
        } else {
            cancelPendingActivitySignal()
            emitActivitySignal(at: now)
        }
    }

    private func emitActivitySignal(at date: Date) {
        lastActivitySignalAt = date
        onUserActivity()
    }

    private func cancelPendingActivitySignal() {
        activityWorkGate.cancel()
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum FocusedField: Hashable {
        case option(String, String)
        case custom(String)
    }
}
