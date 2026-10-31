import SwiftUI

// Shared visual language: material cards, coloured status chips, empty states.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }
}
extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
    func appColorScheme(_ appearance: String) -> some View {
        preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}
struct CardHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var trailing: Trailing
    init(_ title: String, symbol: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title; self.symbol = symbol; self.trailing = trailing()
    }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 18)
            Text(title).font(.headline)
            Spacer(minLength: 8)
            trailing
        }
    }
}
struct EmptyState: View {
    let symbol: String
    let title: String
    let hint: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Text(hint).font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(16)
    }
}
enum StatusTone {
    case ok, busy, problem
    var color: Color { switch self { case .ok: .green; case .busy: .orange; case .problem: .red } }
    static func of(_ value: String) -> StatusTone {
        let lower = value.lowercased()
        if ["failed", "offline", "not installed", "denied", "error"].contains(where: lower.contains) { return .problem }
        if ["ready", "available", "listening"].contains(where: lower.contains) { return .ok }
        return .busy
    }
}
struct StatusPill: View {
    let title: String
    let value: String
    var symbol = "circle.fill"
    var body: some View {
        let tone = StatusTone.of(value)
        HStack(spacing: 6) {
            Circle().fill(tone.color).frame(width: 7, height: 7)
                .shadow(color: tone.color.opacity(0.6), radius: tone == .ok ? 3 : 0)
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(title).fontWeight(.medium)
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: Capsule()).help(title + ": " + value)
    }
}
struct AudioMeter: View {
    let label: String
    let level: Float
    let status: String
    var symbol = "waveform"
    var body: some View {
        let fill = min(1, Double(level) * 8)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(label).font(.caption.weight(.medium))
                Spacer()
                Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(status)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(LinearGradient(colors: [.green, fill > 0.8 ? .orange : .accentColor], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geometry.size.width * fill))
                        .animation(.easeOut(duration: 0.12), value: fill)
                }
            }.frame(height: 6)
            .accessibilityLabel("\(label) audio level").accessibilityValue(String(format: "%.0f percent", fill * 100))
        }
    }
}
struct TranscriptCard: View {
    let confirmed: String
    let interim: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if confirmed.isEmpty && interim.isEmpty {
                    EmptyState(symbol: "text.bubble", title: "Поки тихо", hint: "Мовлення з’явиться тут після старту запису.")
                } else {
                    Text(confirmed).foregroundStyle(.primary)
                    if !interim.isEmpty { Text(interim).foregroundStyle(.secondary).italic().accessibilityLabel("Interim: \(interim)") }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }.defaultScrollAnchor(.bottom)
    }
}
struct AnswerCard: View {
    @ObservedObject var model: ConversationManager
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Відповідь", symbol: "sparkles") {
                if model.generating {
                    ProgressView().controlSize(.small)
                    Button("Стоп", action: model.cancelGeneration).controlSize(.small)
                }
                Button { model.editLatestQuestion() } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help("Виправити розпізнане питання")
                    .popover(isPresented: Binding(get: { model.questionEditing }, set: { if !$0 { model.cancelQuestionEdit() } })) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Уточніть питання перед відповіддю").font(.headline)
                            TextEditor(text: $model.editedQuestion).font(.body).frame(width: 380, height: 100)
                                .scrollContentBackground(.hidden).padding(6)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            HStack { Button("Скасувати") { model.cancelQuestionEdit() }; Spacer(); Button("Відповісти з виправленням") { model.retryEditedQuestion() }.buttonStyle(.borderedProminent) }
                        }.padding(16)
                    }
                Button { model.copyAnswer() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Копіювати відповідь").disabled(model.answer.isEmpty)
            }
            if !model.question.isEmpty {
                Text(model.question).font(.callout.weight(.medium)).lineLimit(compact ? 3 : 5).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if model.answer.isEmpty && !model.generating {
                EmptyState(symbol: "sparkles", title: "Відповідь з’явиться тут", hint: "Поставте питання внизу або натисніть на питання зі списку.")
            } else {
                AnswerWebView(text: model.answer.isEmpty ? "Генерую локально…" : model.answer, streaming: model.generating).frame(minHeight: 90)
            }
            if !model.thinkingText.isEmpty { DisclosureGroup("Міркування моделі") { ScrollView { Text(model.thinkingText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.frame(maxHeight: 120) } }
            if model.answerTruncated { Label("Модель зупинилася на ліміті довжини · збільште контекст", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if let first = model.firstTokenSeconds {
                Label(String(format: "Перший токен %.2f с", first) + (model.generationSeconds.map { String(format: " · усього %.2f с", $0) } ?? ""), systemImage: "bolt")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }.card()
    }
}
