import SwiftUI
struct StatusPill: View {
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 6) { Circle().fill(value.contains("Ready") || value.contains("Available") || value == "Listening" ? Color.green : Color.orange).frame(width: 6, height: 6); Text(title).foregroundStyle(.secondary); Text(value).lineLimit(1) }.font(.caption).padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary.opacity(0.5), in: Capsule()).help(value)
    }
}
struct AudioMeter: View {
    let label: String
    let level: Float
    let status: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(label).font(.caption.weight(.medium)); Spacer(); Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(status) }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor).frame(width: geometry.size.width * min(1, Double(level) * 8))
                }
            }.frame(height: 5).accessibilityLabel("\(label) audio level").accessibilityValue(String(format: "%.0f percent", min(1, Double(level) * 8) * 100))
        }
    }
}
struct TranscriptCard: View {
    let title: String
    let confirmed: String
    let interim: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(confirmed.isEmpty && interim.isEmpty ? "Speech will appear here after capture starts." : confirmed).foregroundStyle(confirmed.isEmpty ? .secondary : .primary)
                    if !interim.isEmpty { Text(interim).foregroundStyle(.secondary).italic().accessibilityLabel("Interim: \(interim)") }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}
struct AnswerCard: View {
    @ObservedObject var model: ConversationManager
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Live AI Answer", systemImage: "sparkles").font(.headline); Spacer(); Button { model.editLatestQuestion() } label: { Image(systemName: "pencil") }.help("Виправити розпізнане питання").popover(isPresented: Binding(get: { model.questionEditing }, set: { if !$0 { model.cancelQuestionEdit() } })) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Уточніть питання перед відповіддю").font(.headline)
                    TextEditor(text: $model.editedQuestion).frame(width: 380, height: 100).border(.quaternary)
                    HStack { Button("Скасувати") { model.cancelQuestionEdit() }; Spacer(); Button("Відповісти з виправленням") { model.retryEditedQuestion() }.buttonStyle(.borderedProminent) }
                }.padding(16)
            }; if model.generating { ProgressView().controlSize(.small); Button("Cancel", action: model.cancelGeneration) }; Button { model.copyAnswer() } label: { Image(systemName: "doc.on.doc") }.help("Copy answer").disabled(model.answer.isEmpty) }
            if !model.question.isEmpty { Text(model.question).font(.subheadline).foregroundStyle(.secondary).lineLimit(compact ? 3 : 5).textSelection(.enabled) }
            AnswerWebView(text: model.answer.isEmpty ? (model.generating ? "Generating locally…" : "Enter a question or start listening.") : model.answer, streaming: model.generating).frame(minHeight: 90)
            if !model.thinkingText.isEmpty { DisclosureGroup("Thinking") { ScrollView { Text(model.thinkingText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.frame(maxHeight: 120) } }
            if model.answerTruncated { Text("Model stopped at its length limit · retry with a larger context window").font(.caption).foregroundStyle(.orange) }
            if let first = model.firstTokenSeconds { Text(String(format: "First token %.2f s", first) + (model.generationSeconds.map { String(format: " · total %.2f s", $0) } ?? "")).font(.caption).foregroundStyle(.secondary) }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}
