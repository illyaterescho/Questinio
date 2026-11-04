import SwiftUI
/// Redraws only its own content when the audio levels change.
struct LevelReader<Content: View>: View {
    @ObservedObject var levels: AudioLevels
    @ViewBuilder let content: (AudioLevels) -> Content
    var body: some View { content(levels) }
}

// Shared visual language: Liquid Glass (macOS 26+) over a soft ambient backdrop,
// with a material fallback on older systems.
/// One spacing/size grid for the whole app.
enum UI {
    static let page: CGFloat = 20      // window content inset
    static let gap: CGFloat = 16       // between cards and rows
    static let inner: CGFloat = 12     // inside cards
    static let control: CGFloat = 34   // every control in a bar
    static let bar: CGFloat = 46       // command bar / composer height
    static let radius: CGFloat = 22    // card corners
}
extension View {
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) { glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape) }
        else { background(.regularMaterial, in: shape).overlay(shape.stroke(.primary.opacity(0.08))) }
    }
    func card(padding: CGFloat = 16) -> some View { self.padding(padding).glass(RoundedRectangle(cornerRadius: UI.radius, style: .continuous)) }
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
            scheme == .dark ? Color(white: 0.07) : Color.white
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
        }.frame(height: 28)
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
/// Small borderless icon with a 28 pt hit target and hover highlight.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                .background(.primary.opacity(hover ? 0.08 : 0), in: Circle()).contentShape(Circle())
        }.buttonStyle(.plain).foregroundStyle(.secondary).onHover { hover = $0 }.help(help)
    }
}
/// Primary action: accent capsule with the same height as bar controls.
struct AccentButton: View {
    let title: String
    var shortcut: String?
    var symbol: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
                if let shortcut { Text(shortcut).font(.system(size: 11, weight: .medium)).opacity(0.75) }
            }.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: UI.control)
            .background(Color.accentColor.opacity(enabled ? 1 : 0.45), in: Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}
/// On/off control with the same metrics as bar chips; filled with the accent colour when on.
struct BarToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    let help: String
    @State private var hover = false
    var body: some View {
        Button { isOn.toggle() } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).frame(height: UI.control)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(hover ? 0.07 : 0)), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).onHover { hover = $0 }.help(help).animation(.snappy(duration: 0.18), value: isOn)
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
        VStack(alignment: .leading, spacing: UI.inner) {
            CardHeader("Відповідь", symbol: "sparkles") {
                if model.generating {
                    ProgressView().controlSize(.small)
                    IconButton(symbol: "stop.circle", help: "Зупинити генерацію", action: model.cancelGeneration)
                }
                IconButton(symbol: "pencil", help: "Виправити розпізнане питання") { model.editLatestQuestion() }
                    .popover(isPresented: Binding(get: { model.questionEditing }, set: { if !$0 { model.cancelQuestionEdit() } })) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Уточніть питання перед відповіддю").font(.headline)
                            TextEditor(text: $model.editedQuestion).font(.body).frame(width: 380, height: 100)
                                .scrollContentBackground(.hidden).padding(6)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            HStack { Button("Скасувати") { model.cancelQuestionEdit() }.glassButton(); Spacer(); Button("Відповісти з виправленням") { model.retryEditedQuestion() }.glassButton(prominent: true) }
                        }.padding(16)
                    }
                IconButton(symbol: "doc.on.doc", help: "Копіювати відповідь") { model.copyAnswer() }.disabled(model.displayedAnswer.isEmpty)
            }
            let live = model.liveAnswerIsLogged
            let pages = model.answerLog.pageCount(liveIsLogged: live)
            let page = model.answerLog.page(liveIsLogged: live)
            if pages > 1 || !model.answerQueue.items.isEmpty {
                HStack(spacing: 6) {
                    if pages > 1 {
                        IconButton(symbol: "chevron.left", help: "Попередня відповідь") { model.answerLog.move(by: -1, liveIsLogged: live) }.disabled(page == 0)
                        Text("\(page + 1) / \(pages)").font(.caption).monospacedDigit()
                        IconButton(symbol: "chevron.right", help: "Наступна відповідь") { model.answerLog.move(by: 1, liveIsLogged: live) }.disabled(page == pages - 1)
                    }
                    if model.answerLog.shownTurn?.interrupted == true { Text("перервано").font(.caption).foregroundStyle(.orange) }
                    Spacer()
                    if !model.answerQueue.items.isEmpty { Label("У черзі: \(model.answerQueue.items.count)", systemImage: "list.number").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !model.displayedQuestion.isEmpty {
                Text(model.displayedQuestion).font(.callout.weight(.medium)).lineLimit(compact ? 3 : 5).textSelection(.enabled)
                    .padding(UI.inner).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if model.displayedAnswer.isEmpty && !model.generating {
                EmptyState(symbol: "sparkles", title: "Відповідь з’явиться тут", hint: "Поставте питання внизу або натисніть на питання зі списку.")
            } else {
                AnswerWebView(text: model.displayedAnswer.isEmpty ? (model.answersUseClaude ? "Генерую через Haiku 5.5…" : "Генерую локально…") : model.displayedAnswer, streaming: model.generating && model.answerLog.shown == nil).frame(minHeight: 90)
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
