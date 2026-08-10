import SwiftUI

/// Журнал действий: кто что удалил или отменил.
///
/// Сервер пишет сюда только необратимое — удаление сообщения, мероприятия,
/// сотрудника, файлов Диска, снятие фото с фотобанка и отмену смены. Смотрит
/// журнал админ и руководитель: реализатору он не отдаётся, потому что общий по
/// организации, а тот видит лишь свои компании.
struct AuditLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var entries: [AuditEntryDTO] = []
    @State private var filter: String = ""
    @State private var isLoading = true

    /// Виды действий, которые сервер пишет в журнал.
    private static let actions: [(key: String, title: String)] = [
        ("", "Все"),
        ("delete_message", "Сообщения"),
        ("delete_event", "Мероприятия"),
        ("delete_worker", "Сотрудники"),
        ("delete_disk_files", "Диск"),
        ("remove_from_photobank", "Фотобанк"),
        ("cancel_shift", "Смены"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: Spacing.s) {
                    filterBar
                    if isLoading {
                        Spacer(); ProgressView().tint(Theme.accent); Spacer()
                    } else if entries.isEmpty {
                        Spacer()
                        EmptyState(icon: "list.bullet.rectangle",
                                   title: "Записей нет",
                                   message: "Здесь появится всё необратимое: удаления и отмены смен.")
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: Spacing.xs) {
                                ForEach(entries) { entry in row(entry) }
                            }
                            .padding(.horizontal, metrics.horizontalPadding)
                            .padding(.bottom, Spacing.m)
                        }
                    }
                }
            }
            .navigationTitle("Журнал действий")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: filter) { Task { await load() } }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.actions, id: \.key) { item in
                    let on = filter == item.key
                    Button { filter = item.key } label: {
                        Text(item.title)
                            .font(.caption.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? Theme.textOnAccent : Theme.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Theme.accent : Theme.panel2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
        }
        .padding(.top, Spacing.s)
    }

    private func row(_ entry: AuditEntryDTO) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: entry.icon).font(.caption).foregroundStyle(Theme.danger)
                Text(entry.actionTitle).font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(when(entry.created_at)).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            if !entry.object.isEmpty {
                Text(entry.object).font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary).lineLimit(2)
            }
            Text([entry.actor_fio, entry.details].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(2)
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private func when(_ iso: String) -> String {
        guard let date = DateParse.iso(iso) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM, HH:mm"
        return f.string(from: date)
    }

    private func load() async {
        let path = filter.isEmpty ? "/api/audit" : "/api/audit?action=\(filter)"
        entries = (try? await APIClient.shared.get(path, as: [AuditEntryDTO].self)) ?? []
        isLoading = false
    }
}
