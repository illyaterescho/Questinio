import SwiftUI

// Shared visual language: Liquid Glass (macOS 26+) over a soft ambient backdrop,
// with a material fallback on older systems.
extension View {
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) { glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape) }
        else { background(.regularMaterial, in: shape).overlay(shape.stroke(.primary.opacity(0.08))) }
    }
    func card(padding: CGFloat = 16) -> some View { self.padding(padding).glass(RoundedRectangle(cornerRadius: 22, style: .continuous)) }
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) { if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) } }
        else { if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) } }
    }
    func appColorScheme(_ appearance: String) -> some View {
        preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: spacing) { content } } else { content }
    }
}
/// Soft colour fields behind the glass so it has something to refract.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let strength = scheme == .dark ? 0.32 : 0.22
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle().fill(Color.blue.opacity(strength)).frame(width: 520).blur(radius: 140).offset(x: -260, y: -220)
            Circle().fill(Color.purple.opacity(strength * 0.8)).frame(width: 460).blur(radius: 150).offset(x: 320, y: -120)
            Circle().fill(Color.teal.opacity(strength * 0.7)).frame(width: 480).blur(radius: 150).offset(x: 120, y: 300)
        }.ignoresSafeArea().allowsHitTesting(false)
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
        .font(.caption).padding(.horizontal, 11).padding(.vertical, 7)
        .glass(Capsule()).help(title + ": " + value)
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
                    Capsule().fill(.primary.opacity(0.08))
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
                    Button("Стоп", action: model.cancelGeneration).controlSize(.small).glassButton()
                }
                Button { model.editLatestQuestion() } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help("Виправити розпізнане питання")
                    .popover(isPresented: Binding(get: { model.questionEditing }, set: { if !$0 { model.cancelQuestionEdit() } })) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Уточніть питання перед відповіддю").font(.headline)
                            TextEditor(text: $model.editedQuestion).font(.body).frame(width: 380, height: 100)
                                .scrollContentBackground(.hidden).padding(6)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            HStack { Button("Скасувати") { model.cancelQuestionEdit() }.glassButton(); Spacer(); Button("Відповісти з виправленням") { model.retryEditedQuestion() }.glassButton(prominent: true) }
                        }.padding(16)
                    }
                Button { model.copyAnswer() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Копіювати відповідь").disabled(model.answer.isEmpty)
            }
            if !model.question.isEmpty {
                Text(model.question).font(.callout.weight(.medium)).lineLimit(compact ? 3 : 5).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
