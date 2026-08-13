import SwiftUI

/// Жалобы, которые мне разбирать.
///
/// Жалоба всегда привязана к мероприятию и уходит тому, кто завёл чат; если
/// жалуются на него самого — руководителю. Супер-админ видит все по организации.
/// Копия падает в служебный чат «Жалобы», а здесь — список с разбором.
struct ComplaintsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var items: [ComplaintDTO] = []
    @State private var isLoading = true
    @State private var busyId: Int?
    @State private var errorText: String?
    /// Справочник по id — по нему имена в карточке открывают профиль.
    @State private var people: [String: User] = [:]
    @State private var openUser: User?

    private var pending: [ComplaintDTO] { items.filter(\.isNew) }
    private var done: [ComplaintDTO] { items.filter { !$0.isNew } }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else if items.isEmpty {
                    EmptyState(icon: "checkmark.bubble",
                               title: "Жалоб нет",
                               message: "Сюда попадают жалобы по мероприятиям, за которые вы отвечаете.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spacing.s) {
                            if let errorText { ErrorBanner(text: errorText) }
                            if !pending.isEmpty {
                                section("Разобрать", pending)
                            }
                            if !done.isEmpty {
                                section("Разобрано", done)
                            }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle(pending.isEmpty ? "Жалобы" : "Жалобы · \(pending.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $openUser) { user in
                NavigationStack {
                    UserProfileView(user: user).environmentObject(session)
                }
            }
        }
    }

    private func section(_ title: String, _ list: [ComplaintDTO]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            ForEach(list) { card($0) }
        }
    }

    private func card(_ item: ComplaintDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: 6) {
                    Image(systemName: item.isNew ? "exclamationmark.bubble.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(item.isNew ? Theme.danger : Theme.success)
                    // Имя открывает карточку: разбирать жалобу, не зная, кто это,
                    // невозможно — а по фамилии в списке человека не найти.
                    nameButton("На ", id: item.about_id, fio: item.about_fio ?? "сотрудника",
                               font: Typography.callout.weight(.medium))
                    Spacer(minLength: 0)
                    Text(when(item.created_at)).font(.caption2).foregroundStyle(Theme.textSecondary)
                }

                if let event = item.event_name, !event.isEmpty {
                    // Мероприятие кликается: разбирать жалобу без чата не выйдет.
                    Button {
                        Router.shared.openChat(id: "chat-\(item.event_id)")
                        dismiss()
                    } label: {
                        Label(event, systemImage: "bubble.left")
                            .font(.caption).foregroundStyle(Theme.accent).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }

                Text(item.body)
                    .font(Typography.callout).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.s) {
                    nameButton("от ", id: item.author_id, fio: item.author_fio ?? "—",
                               font: .caption2, tint: Theme.textSecondary)
                    Spacer(minLength: 0)
                    if item.isNew {
                        if busyId == item.id {
                            ProgressView().tint(Theme.accent)
                        } else {
                            Button("Разобрано") { Task { await close(item) } }
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                    } else if let who = item.closed_fio, !who.isEmpty {
                        Text("разобрал(а) " + who)
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    /// Имя как кнопка — если человек нашёлся в справочнике. Не нашёлся (уволен,
    /// гость по ссылке) — обычный текст, а не кнопка, ведущая в никуда.
    @ViewBuilder
    private func nameButton(_ prefix: String, id: Int, fio: String,
                            font: Font, tint: Color = Theme.textPrimary) -> some View {
        if let user = people[String(id)] {
            Button { openUser = user } label: {
                Text(prefix + fio).font(font).foregroundStyle(Theme.accent).lineLimit(1)
            }
            .buttonStyle(.plain)
        } else {
            Text(prefix + fio).font(font).foregroundStyle(tint).lineLimit(1)
        }
    }

    private func when(_ iso: String) -> String {
        guard let date = DateParse.iso(iso) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM"
        return f.string(from: date)
    }

    private func close(_ item: ComplaintDTO) async {
        busyId = item.id
        errorText = nil
        defer { busyId = nil }
        do {
            try await PeopleExtras.closeComplaint(id: item.id)
            Haptics.success()
            await load()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func load() async {
        async let list = PeopleExtras.complaints()
        async let directory = DirectoryCache.colleagues()
        let (loaded, users) = await (list, directory)
        items = loaded.items
        people = Dictionary(users.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        isLoading = false
    }
}

/// Пожаловаться на человека — из карточки участника мероприятия.
struct ComplaintComposer: View {
    let dealId: String
    let about: User

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Text("Жалоба на " + about.fullName)
                                    .font(Typography.headline).foregroundStyle(Theme.textPrimary)
                                Text("Уйдёт тому, кто завёл этот чат. Он же её и разберёт — в переписке жалоба не появится.")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                        }

                        GlassCard {
                            TextField("Что случилось", text: $text, axis: .vertical)
                                .lineLimit(4...10)
                                .foregroundStyle(Theme.textPrimary)
                        }

                        if let errorText { ErrorBanner(text: errorText) }

                        PrimaryButton(title: "Отправить", isLoading: busy,
                                      isEnabled: !busy && !text.trimmingCharacters(in: .whitespaces).isEmpty) {
                            Task { await send() }
                        }
                    }
                    .padding(Spacing.m)
                }
            }
            .navigationTitle("Жалоба")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } } }
        }
    }

    private func send() async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            try await PeopleExtras.complain(dealId: dealId, aboutId: about.id,
                                            text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            Haptics.success()
            dismiss()
        } catch {
            errorText = message(for: error)
            Haptics.warning()
        }
    }

    private func message(for error: Error) -> String {
        guard case let APIError.http(_, serverMessage) = error else { return error.localizedDescription }
        switch serverMessage {
        case "no_recipient":     return "Жалобу некому адресовать: у мероприятия нет ответственного."
        case "not_member_about": return "Этот человек не в составе мероприятия."
        case "bad_about":        return "На себя пожаловаться нельзя."
        default:                 return serverMessage ?? error.localizedDescription
        }
    }
}
