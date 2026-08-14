import SwiftUI

/// Выбор компании (бренда) мероприятия. Список приходит с сервера
/// (`GET /api/companies`); он же определяет папку выгрузки фото на Диске —
/// «Компания/Мероприятие/…».
struct CompanyPicker: View {
    @EnvironmentObject private var session: AppSession
    /// id выбранной компании; nil — без компании.
    @Binding var selection: Int?
    @State private var companies: [CompanyDTO] = []

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Компания").font(Typography.headline).foregroundStyle(Theme.textPrimary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(title: "Без компании", isOn: selection == nil) { selection = nil }
                        ForEach(companies) { company in
                            chip(title: company.name, isOn: selection == company.id) { selection = company.id }
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .horizontalStrip()

                Text("Определяет папку выгрузки фото на общем диске.")
                    .font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .task { companies = await session.directory.fetchCompanies() }
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) { action() }
            Haptics.tap()
        } label: {
            Text(title)
                .font(.caption.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Theme.textOnAccent : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Theme.accent : Theme.panel2, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
