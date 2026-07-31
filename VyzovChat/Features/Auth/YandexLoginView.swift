import SwiftUI
@preconcurrency import WebKit

/// Вход через Яндекс.
///
/// Сервер завершает вход **редиректом на веб-адрес** `https://vyzovchat.ru/?token=…`,
/// а не на свою схему приложения. Поэтому штатный `ASWebAuthenticationSession` здесь
/// не годится — ему нужна ссылка возврата с известной схемой. Открываем окно входа
/// и ловим этот редирект: токен забираем из адреса и дальше живём как после
/// обычного входа.
///
/// Правильнее было бы попросить сервер поддержать возврат на `vyzovchat://auth`,
/// тогда можно перейти на системный диалог входа. Пока обходимся этим.
struct YandexLoginView: View {
    let onToken: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                YandexWebView(isLoading: $isLoading) { token in
                    onToken(token)
                    dismiss()
                }
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView().tint(Theme.accent)
                }
            }
            .navigationTitle("Вход через Яндекс")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } } }
        }
    }
}

private struct YandexWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        // Отдельное непостоянное хранилище: чужой аккаунт Яндекса не должен
        // оставаться в приложении после выхода.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        if let url = URL(string: AppConfig.baseURL.absoluteString + "/api/auth/yandex/login") {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: YandexWebView
        private var finished = false

        init(_ parent: YandexWebView) { self.parent = parent }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Вход завершён, когда сервер возвращает нас на свою страницу с токеном.
            if let url = navigationAction.request.url, let token = Self.token(in: url), !finished {
                finished = true
                decisionHandler(.cancel)
                DispatchQueue.main.async { self.parent.onToken(token) }
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        private static func token(in url: URL) -> String? {
            guard url.host == AppConfig.baseURL.host,
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let token = items.first(where: { $0.name == "token" })?.value,
                  !token.isEmpty else { return nil }
            return token
        }
    }
}
