import SwiftUI
import UIKit

/// Ввод ссылки-приглашения руками.
///
/// Ссылку присылают в переписке, и человек копирует её целиком. Универсальные
/// ссылки (открывать `https://vyzovchat.ru/join/…` сразу приложением) требуют
/// файла apple-app-site-association на сервере — сервер чужой, поэтому здесь
/// просто разбираем вставленный текст.
struct InvitePasteView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var link = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: Spacing.m) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            GlassField(placeholder: "https://vyzovchat.ru/join/…",
                                       icon: "link", text: $link)
                            if let errorText { ErrorBanner(text: errorText) }
                            PrimaryButton(title: "Открыть приглашение", isLoading: false,
                                          isEnabled: !link.trimmingCharacters(in: .whitespaces).isEmpty) {
                                if session.openInvite(rawLink: link) {
                                    dismiss()
                                } else {
                                    errorText = "Это не похоже на ссылку-приглашение. Вставьте её целиком."
                                }
                            }
                            Button("Вставить из буфера") {
                                link = UIPasteboard.general.string ?? link
                            }
                            .font(.caption).foregroundStyle(Theme.accent)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, Spacing.m)
            }
            .navigationTitle("Приглашение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } } }
        }
    }
}

/// Приём приглашения по ссылке — то же, что страница `/join/<token>` в вебе.
///
/// Три случая, и они не пересекаются:
/// * **склад** — пароля нет вовсе, человек только называет себя; имя должно быть
///   уникальным в мероприятии, иначе два «Ивана» слились бы в одну учётку и в
///   чеклисте было бы не понять, кто отмечал;
/// * **подрядчик** — регистрируется или входит уже заведённым логином;
/// * **уже в составе** — форму не показываем: гость упёрся бы в «имя занято»
///   собственным именем.
struct JoinView: View {
    let token: String
    /// Закрыть экран (и убрать приглашение из ожидающих).
    let onClose: () -> Void

    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var info: InviteInfoDTO?
    @State private var isLoading = true
    @State private var busy = false
    @State private var errorText: String?

    // Поля формы
    @State private var mode: Mode = .register
    @State private var fio = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var login = ""
    @State private var pass = ""

    private enum Mode: String, CaseIterable, Identifiable {
        case register = "Регистрация"
        case login = "Вход"
        var id: String { rawValue }
    }

    private var isGuest: Bool { info?.role == "storekeeper" || info?.role == "warehouse" }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else if let info {
                    ScrollView {
                        VStack(spacing: Spacing.m) {
                            header(info)
                            if let errorText { ErrorBanner(text: errorText) }
                            if info.member == true {
                                alreadyMember
                            } else if isGuest {
                                guestForm
                            } else {
                                contractorForm
                            }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.m)
                    }
                } else {
                    EmptyState(icon: "link.badge.plus",
                               title: "Ссылка не действует",
                               message: "Приглашение просрочено или уже использовано. Попросите новую ссылку.")
                }
            }
            .navigationTitle("Приглашение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { onClose() } } }
            .task { await load() }
        }
    }

    private func header(_ info: InviteInfoDTO) -> some View {
        GlassCard {
            VStack(spacing: Spacing.xxs) {
                Text(info.event_name ?? "Мероприятие")
                    .font(Typography.headline).foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(isGuest ? "Приглашение · кладовщик" : "Приглашение · подрядчик")
                    .font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var alreadyMember: some View {
        GlassCard {
            VStack(spacing: Spacing.s) {
                Text("Вы уже в этом мероприятии.")
                    .font(Typography.callout).foregroundStyle(Theme.textPrimary)
                PrimaryButton(title: "Открыть чат", isLoading: false, isEnabled: true) {
                    if let id = info?.event_id { Router.shared.openChat(id: "chat-\(id)") }
                    onClose()
                }
            }
        }
    }

    /// Склад: только имя. Полное — по нему в чеклисте видно, кто отмечал.
    private var guestForm: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                GlassField(placeholder: "Имя и фамилия", icon: "person.fill", text: $fio)
                PrimaryButton(title: "Войти в чат", isLoading: busy,
                              isEnabled: !busy && !fio.trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task { await accept(.guest(fio: fio.trimmingCharacters(in: .whitespaces))) }
                }
                Text("Пароль не нужен: вход по этой ссылке. Назовитесь так, чтобы вас узнали в чеклисте.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var contractorForm: some View {
        VStack(spacing: Spacing.s) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            GlassCard {
                VStack(spacing: Spacing.s) {
                    if mode == .register {
                        GlassField(placeholder: "ФИО", icon: "person.fill", text: $fio)
                        GlassField(placeholder: "Телефон", icon: "phone.fill",
                                   keyboard: .phonePad, text: $phone)
                        GlassField(placeholder: "E-mail", icon: "envelope.fill", text: $email)
                    }
                    GlassField(placeholder: "Логин", icon: "at", text: $login)
                    GlassField(placeholder: mode == .register ? "Пароль (от 4 символов)" : "Пароль",
                               icon: "lock.fill", isSecure: true, text: $pass)

                    PrimaryButton(title: mode == .register ? "Присоединиться" : "Войти",
                                  isLoading: busy, isEnabled: canSubmit) {
                        Task {
                            if mode == .register {
                                await accept(.register(fio: fio.trimmingCharacters(in: .whitespaces),
                                                       phone: phone, email: email,
                                                       login: login.trimmingCharacters(in: .whitespaces),
                                                       pass: pass))
                            } else {
                                await accept(.login(login: login.trimmingCharacters(in: .whitespaces),
                                                    pass: pass))
                            }
                        }
                    }
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard !busy else { return false }
        let hasLogin = !login.trimmingCharacters(in: .whitespaces).isEmpty
        if mode == .login { return hasLogin && !pass.isEmpty }
        return hasLogin && pass.count >= 4 && !fio.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Действия

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        info = try? await InviteService.info(token: token)
    }

    /// Явно на главном потоке: внутри трогаем сессию и роутер — они @MainActor.
    @MainActor
    private func accept(_ body: AcceptInviteRequest) async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let resp = try await InviteService.accept(token: token, body)
            // Приглашение — это ещё и вход: сервер отдаёт токен новой сессии.
            TokenStore.token = resp.token
            session.handleSignedIn(User(dto: resp.worker))
            if let id = resp.event_id { Router.shared.openChat(id: "chat-\(id)") }
            Haptics.success()
            onClose()
        } catch {
            errorText = message(for: error)
            Haptics.warning()
        }
    }

    /// Ошибки сервера словами. `name_taken` — самая частая у склада: на одном
    /// мероприятии уже есть человек с таким именем.
    private func message(for error: Error) -> String {
        guard case let APIError.http(status, serverMessage) = error else {
            return error.localizedDescription
        }
        switch serverMessage {
        case "name_taken":
            return "На этом мероприятии уже есть человек с таким именем. Укажите имя и фамилию полностью."
        case "login_taken":
            return "Такой логин уже занят — придумайте другой или войдите существующим."
        case "bad_credentials":
            return "Неверный логин или пароль."
        case "invalid_or_expired":
            return "Ссылка не действует: приглашение просрочено или уже использовано."
        case "invalid":
            return "Заполните ФИО, логин и пароль (от 4 символов)."
        default:
            return status == 429
                ? "Слишком много попыток. Подождите немного и попробуйте снова."
                : (serverMessage ?? "Не удалось принять приглашение")
        }
    }
}
