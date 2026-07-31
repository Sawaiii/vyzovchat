import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @StateObject private var vm: AuthViewModel
    @State private var showPasswordReset = false
    @State private var showYandex = false
    @State private var providers: AuthProvidersDTO?

    init() {
        // временный vm; реальный создаётся в onAppear через session
        _vm = StateObject(wrappedValue: AuthViewModel(auth: MockAuthService(), onSuccess: { _ in }))
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header

                    VStack(spacing: Spacing.s) {
                        GlassField(placeholder: "Логин", icon: "person.fill",
                                   textContentType: .username,
                                   text: $vm.login)
                        GlassField(placeholder: "Пароль", icon: "lock.fill",
                                   isSecure: true, textContentType: .password,
                                   text: $vm.password)
                    }

                    if let error = vm.errorText {
                        ErrorBanner(text: error)
                    }

                    PrimaryButton(title: "Войти", isLoading: vm.isLoading,
                                  isEnabled: vm.loginEnabled) {
                        UIApplication.shared.endEditing()   // прячем клавиатуру
                        Task { await vm.login() }
                    }

                    // Кнопку показываем, только если вход через Яндекс включён
                    // на сервере, — иначе она вела бы в никуда.
                    if providers?.yandex == true {
                        SecondaryButton(title: "Войти через Яндекс", icon: "person.badge.key.fill") {
                            showYandex = true
                        }
                    }

                    Button("Забыли пароль?") { showPasswordReset = true }
                        .font(Typography.caption)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Вход")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { rebind() }
        .task {
            providers = try? await APIClient.shared.get("/api/auth/providers", as: AuthProvidersDTO.self)
        }
        .sheet(isPresented: $showPasswordReset) { PasswordResetView() }
        .sheet(isPresented: $showYandex) {
            YandexLoginView { token in Task { await finishYandex(token) } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("С возвращением 👋")
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            Text("Войдите по логину и паролю")
                .font(Typography.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Токен из Яндекс-входа равнозначен токену обычного входа: сохраняем его
    /// и подтягиваем карточку сотрудника тем же путём, что при восстановлении сессии.
    private func finishYandex(_ token: String) async {
        TokenStore.token = token
        if let user = await session.auth.restoreSession() {
            Haptics.success()
            session.handleSignedIn(user)
        } else {
            TokenStore.token = nil
            Haptics.warning()
            vm.errorText = "Этот Яндекс-аккаунт не привязан ни к одному сотруднику"
        }
    }

    /// Привязываем vm к сервисам сессии (session доступен только в body/onAppear).
    private func rebind() {
        vm.rebindIfNeeded(auth: session.auth) { user in
            session.handleSignedIn(user)
        }
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(Typography.callout)
        }
        .foregroundStyle(Theme.danger)
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
    }
}
