import SwiftUI
@preconcurrency import WebKit

/// Привязка и отвязка Яндекс-аккаунта в своём профиле.
///
/// Вход через Яндекс у нас уже есть (`YandexLoginView`), но привязать Яндекс к
/// **существующей** учётке — отдельный сценарий: сервер выдаёт разовую ссылку
/// (`POST /api/auth/yandex/link`) и в конце возвращает человека на свою страницу
/// с пометкой `?ya=linked|taken|unknown`. Ловим её так же, как токен при входе.
enum YandexAccount {

    /// Привязан ли Яндекс. Признак приходит только в карточке одного сотрудника.
    static func isLinked(workerId: String) async -> Bool {
        let dto = try? await APIClient.shared.get("/api/workers/\(workerId)", as: WorkerDTO.self)
        return dto?.yandex_linked ?? false
    }

    /// Ссылка на страницу согласия Яндекса для привязки.
    static func linkURL() async throws -> URL {
        struct LinkDTO: Decodable { let url: String }
        let dto = try await APIClient.shared.post("/api/auth/yandex/link",
                                                  json: EmptyBody(), as: LinkDTO.self)
        guard let url = URL(string: dto.url) else { throw APIError.transport("Некорректная ссылка Яндекса") }
        return url
    }

    static func unlink(workerId: String) async throws {
        _ = try await APIClient.shared.delete("/api/workers/\(workerId)/yandex", as: OKDTO.self)
    }
}

/// Окно привязки: ведёт человека по страницам Яндекса и закрывается, когда
/// сервер вернул его к себе с результатом.
struct YandexLinkView: View {
    let url: URL
    /// linked — привязали, taken — этот Яндекс уже за кем-то, unknown — прочее.
    let onFinish: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                YandexLinkWebView(url: url, isLoading: $isLoading) { result in
                    onFinish(result)
                    dismiss()
                }
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView().tint(Theme.accent)
                }
            }
            .navigationTitle("Привязка Яндекса")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } } }
        }
    }
}

private struct YandexLinkWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    let onResult: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        // Непостоянное хранилище: чужой аккаунт Яндекса не должен оставаться
        // в приложении после привязки.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: YandexLinkWebView
        private var finished = false

        init(_ parent: YandexLinkWebView) { self.parent = parent }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, let result = Self.result(in: url), !finished {
                finished = true
                decisionHandler(.cancel)
                DispatchQueue.main.async { self.parent.onResult(result) }
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

        private static func result(in url: URL) -> String? {
            guard url.host == AppConfig.baseURL.host,
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let value = items.first(where: { $0.name == "ya" })?.value else { return nil }
            return value
        }
    }
}
