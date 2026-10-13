import SwiftUI
import WebKit
import AppKit

/// Local Markdown + KaTeX; CSP disables outbound requests and model HTML is sanitized.
struct AnswerWebView: NSViewRepresentable {
    let text: String
    let streaming: Bool
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator; view.setValue(false, forKey: "drawsBackground")
        context.coordinator.view = view
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "AnswerRenderer") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(text: text, dark: colorScheme == .dark, streaming: streaming)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { coordinator.pending?.cancel(); view.navigationDelegate = nil }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        weak var view: WKWebView?
        var ready = false
        var text = ""; var dark = false; var streaming = false
        var pending: Task<Void, Never>?
        func update(text: String, dark: Bool, streaming: Bool) {
            guard self.text != text || self.dark != dark || self.streaming != streaming else { return }
            self.text = text; self.dark = dark; self.streaming = streaming
            guard ready, pending == nil else { return }
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                self.pending = nil; self.render()
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render() }
        private func render() {
            guard let data = try? JSONSerialization.data(withJSONObject: [text]), let json = String(data: data, encoding: .utf8) else { return }
            view?.evaluateJavaScript("window.renderAnswer(\(json)[0],\(dark),\(streaming))")
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel) }
        }
    }
}
