import SwiftUI

/// Корневой роутер: показывает загрузку, экран входа или основной интерфейс.
struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ZStack {
            Theme.appBackground.ignoresSafeArea()

            switch session.authState {
            case .loading:
                LaunchView()
                    .transition(.opacity)
            case .signedOut:
                AuthFlowView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .signedIn:
                MainTabView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.45), value: session.authState)
        // Приглашение перекрывает всё: по ссылке приходят и те, кто ещё не вошёл
        // (гость склада), и те, кто уже сидит в приложении под своим логином.
        .fullScreenCover(isPresented: Binding(
            get: { session.pendingInvite != nil },
            set: { if !$0 { session.pendingInvite = nil } })
        ) {
            if let token = session.pendingInvite {
                JoinView(token: token) { session.pendingInvite = nil }
                    .environmentObject(session)
            }
        }
        .task {
            await session.bootstrap()
        }
    }
}

/// Стартовый сплэш с логотипом.
private struct LaunchView: View {
    @State private var appear = false

    var body: some View {
        VStack(spacing: Spacing.m) {
            BrandMark(size: 96)
                .scaleEffect(appear ? 1 : 0.85)
                .opacity(appear ? 1 : 0)
            Text("Vyzov Chat")
                .font(Typography.largeTitle)
                .foregroundStyle(Theme.textPrimary)
                .opacity(appear ? 1 : 0)
            ProgressView()
                .tint(Theme.accent)
                .padding(.top, Spacing.s)
                .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.6)) { appear = true }
        }
    }
}

#Preview {
    RootView().environmentObject(AppSession())
}
