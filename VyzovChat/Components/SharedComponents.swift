import SwiftUI

/// Пустое состояние со стеклянной иллюстрацией.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(width: 96, height: 96)
                .glass(cornerRadius: 28)
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Typography.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }
}

/// Скелетон-заглушка списка на время загрузки.
struct LoadingList: View {
    @Environment(\.adaptiveMetrics) private var metrics
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: Spacing.s) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: Spacing.s) {
                    Circle().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).frame(height: 14).frame(maxWidth: 160)
                        RoundedRectangle(cornerRadius: 6).frame(height: 12).frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(.gray.opacity(shimmer ? 0.15 : 0.28))
                .padding(Spacing.s)
                .glass(cornerRadius: Theme.cornerMedium, elevated: false)
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, Spacing.s)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

/// Форматирование дат для списков и сообщений.
/// Форматтеры кэшируем: `DateFormatter()` дорогой в создании, а `time()`/
/// `daySeparator()` вызываются для каждого видимого сообщения на каждом рендере.
/// `DateFormatter` потокобезопасен на чтение (только форматирование), поэтому
/// общие static-инстансы безопасны.
enum RelativeDate {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = pattern
        return f
    }
    private static let hm = formatter("HH:mm")
    private static let dMonShort = formatter("d MMM")
    private static let dMonFull = formatter("d MMMM")

    static func short(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return hm.string(from: date) }
        if Calendar.current.isDateInYesterday(date) { return "вчера" }
        return dMonShort.string(from: date)
    }

    static func time(_ date: Date) -> String {
        hm.string(from: date)
    }

    static func daySeparator(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(date) { return "Вчера" }
        return dMonFull.string(from: date)
    }
}
