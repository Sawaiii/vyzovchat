import SwiftUI

/// Сброс пароля по коду из письма.
///
/// Сервер намеренно отвечает одинаково независимо от того, есть ли такая почта:
/// по ответу нельзя узнать, зарегистрирован ли адрес. Поэтому после первого шага
/// всегда переходим к вводу кода и не обещаем, что письмо точно ушло.
struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    private enum Step { case email, code }
    @State private var step: Step = .email

    @State private var email = ""
    @State private var code = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var doneText: String?

    private var canSend: Bool {
        !busy && email.contains("@") && email.count > 4
    }
    private var canReset: Bool {
        !busy && code.count >= 4 && pass.count >= 4
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        header
                        switch step {
                        case .email: emailStep
                        case .code:  codeStep
                        }
                        if let errorText { ErrorBanner(text: errorText) }
                        if let doneText {
                            Text(doneText).font(Typography.caption).foregroundStyle(Theme.success)
                        }
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, Spacing.l)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Смена пароля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(step == .email ? "Куда прислать код" : "Введите код из письма")
                .font(Typography.title).foregroundStyle(Theme.textPrimary)
            Text(step == .email
                 ? "Код придёт на почту, указанную в вашем профиле."
                 : "Код действует 30 минут. Если письма нет — проверьте папку «Спам».")
                .font(Typography.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    private var emailStep: some View {
        VStack(spacing: Spacing.s) {
            GlassField(placeholder: "Почта", icon: "envelope.fill",
                       keyboard: .emailAddress, textContentType: .emailAddress, text: $email)
            PrimaryButton(title: "Выслать код", isLoading: busy, isEnabled: canSend) {
                Task { await requestCode() }
            }
        }
    }

    private var codeStep: some View {
        VStack(spacing: Spacing.s) {
            GlassField(placeholder: "Код из письма", icon: "number",
                       keyboard: .numberPad, text: $code)
            GlassField(placeholder: "Новый пароль (от 4 символов)", icon: "lock.fill",
                       isSecure: true, textContentType: .newPassword, text: $pass)
            PrimaryButton(title: "Сменить пароль", isLoading: busy, isEnabled: canReset) {
                Task { await reset() }
            }
            Button("Ввести другую почту") { step = .email; errorText = nil; doneText = nil }
                .font(Typography.caption).foregroundStyle(Theme.accent)
        }
    }

    private func requestCode() async {
        busy = true
        errorText = nil
        defer { busy = false }
        _ = try? await APIClient.shared.post(
            "/api/password/request",
            json: PasswordRequestBody(email: email.trimmingCharacters(in: .whitespaces)),
            as: OKDTO.self)
        // Ответ одинаковый для существующей и несуществующей почты — сообщаем
        // ровно то, что знаем сами.
        doneText = "Если такая почта есть в системе, письмо с кодом уже отправлено."
        step = .code
        Haptics.tap()
    }

    private func reset() async {
        busy = true
        errorText = nil
        doneText = nil
        defer { busy = false }
        do {
            _ = try await APIClient.shared.post(
                "/api/password/reset",
                json: PasswordResetBody(email: email.trimmingCharacters(in: .whitespaces),
                                        code: code.trimmingCharacters(in: .whitespaces),
                                        pass: pass),
                as: OKDTO.self)
            Haptics.success()
            doneText = "Пароль изменён. Войдите с новым паролем."
            dismiss()
        } catch {
            Haptics.warning()
            errorText = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        guard case let APIError.http(_, code) = error, let code else { return error.localizedDescription }
        switch code {
        case "bad_code", "invalid_code": return "Неверный или просроченный код"
        case "pass_short":               return "Пароль должен быть не короче 4 символов"
        default:                         return error.localizedDescription
        }
    }
}
