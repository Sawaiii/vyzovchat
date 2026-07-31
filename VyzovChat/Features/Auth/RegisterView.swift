import SwiftUI

/// Саморегистрация: ФИО, логин, пароль (создаёт обычного сотрудника).
struct RegisterView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @StateObject private var vm = AuthViewModel(auth: MockAuthService(), onSuccess: { _ in })

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header

                    VStack(spacing: Spacing.s) {
                        GlassField(placeholder: "Код приглашения", icon: "key.fill",
                                   text: $vm.invite)
                        GlassField(placeholder: "ФИО", icon: "person.fill",
                                   textContentType: .name, text: $vm.fio)
                        GlassField(placeholder: "Логин", icon: "at",
                                   textContentType: .username, text: $vm.login)
                        GlassField(placeholder: "Почта (для сброса пароля)", icon: "envelope.fill",
                                   textContentType: .emailAddress, text: $vm.email)
                        GlassField(placeholder: "Пароль (от 4 символов)", icon: "lock.fill",
                                   isSecure: true, textContentType: .newPassword,
                                   text: $vm.password)
                    }

                    if let error = vm.errorText { ErrorBanner(text: error) }

                    PrimaryButton(title: "Создать аккаунт", isLoading: vm.isLoading,
                                  isEnabled: vm.registerEnabled) {
                        UIApplication.shared.endEditing()
                        Task { await vm.register() }
                    }

                    Text("Код приглашения выдаёт администратор. Такой аккаунт открывает Диск и Фотобанк; чаты появятся, когда вас добавят в мероприятие.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Регистрация")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.rebindIfNeeded(auth: session.auth) { user in
                session.handleSignedIn(user)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Создание аккаунта")
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            Text("Придумайте логин и пароль для входа")
                .font(Typography.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
