import SwiftUI

/// Приветственный экран с переходом на вход и регистрацию.
struct AuthFlowView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()

                VStack(spacing: Spacing.l) {
                    Spacer()

                    VStack(spacing: Spacing.m) {
                        BrandMark(size: 92)
                        VStack(spacing: Spacing.xxs) {
                            Text("Vyzov Chat")
                                .font(Typography.largeTitle)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Рабочий мессенджер для выездных команд")
                                .font(Typography.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)

                    Spacer()

                    VStack(spacing: Spacing.s) {
                        NavigationLink {
                            LoginView().environmentObject(session)
                        } label: {
                            Text("Войти")
                                .font(Typography.button)
                                .foregroundStyle(Theme.textOnAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Theme.accentGradient, in: Capsule())
                                .shadow(color: Theme.accent.opacity(0.45), radius: 16, y: 8)
                        }

                        NavigationLink {
                            RegisterView().environmentObject(session)
                        } label: {
                            Text("Регистрация")
                                .font(Typography.button)
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .glass(cornerRadius: 27, elevated: false)
                        }
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 30)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.bottom, Spacing.xl)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.7)) { appear = true }
        }
    }
}
