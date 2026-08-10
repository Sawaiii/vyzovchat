import SwiftUI

/// Сообщение, по которому смотрим список ознакомившихся (обёртка для `sheet(item:)`).
struct AckTarget: Identifiable {
    let id: String
}

/// Кто ознакомился с вводными из сделки или с важным объявлением, а кто ещё нет.
///
/// В списке только те, кому отмечаться положено по роли в мероприятии (участник
/// и старший): админ чата, кладовщик и наблюдатель отметки не ставят — будь они
/// в списке, он никогда не стал бы полным.
struct AckListView: View {
    let messageId: String
    /// Кто грузит список — модель чата, у неё уже есть путь к серверу.
    let load: (String) async -> [AckPersonDTO]

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [AckPersonDTO] = []
    @State private var isLoading = true

    private var done: Int { rows.filter(\.done).count }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else if rows.isEmpty {
                    EmptyState(icon: "person.2",
                               title: "Отмечаться некому",
                               message: "В составе нет ни участников, ни старших — отметку ставят только они.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(rows) { person in row(person) }
                        }
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle(isLoading ? "Ознакомление" : "Ознакомились \(done) из \(rows.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task {
                rows = await load(messageId)
                isLoading = false
            }
        }
    }

    private func row(_ person: AckPersonDTO) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: person.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(person.done ? Theme.success : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.fio).font(Typography.callout).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(EventRole(person.role).title.lowercased())
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(person.done ? whenText(person.at) : "ещё нет")
                .font(.caption2)
                .foregroundStyle(person.done ? Theme.textSecondary : Theme.warning)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    /// Время отметки. Дату показываем, только если это не сегодня, — иначе
    /// строка «10.08 14:32» рядом с сегодняшними отметками просто шумит.
    private func whenText(_ iso: String?) -> String {
        guard let date = DateParse.iso(iso) else { return "отмечен" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM, HH:mm"
        return f.string(from: date)
    }
}
