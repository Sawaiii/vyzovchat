import SwiftUI

/// Куда пересылаем: в чат мероприятия или в личную переписку с человеком.
enum ForwardTarget {
    case chat(Chat)
    case person(User)
}

/// Выбор адресата пересылки.
///
/// Две вкладки, как в вебе: мероприятия и люди. Люди — весь справочник, а не
/// только те, с кем уже есть переписка: переслать «человеку, которому я ещё не
/// писал» — обычное дело, и заводить ради этого пустой чат руками незачем.
struct ForwardPickerView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let onPick: (ForwardTarget) -> Void

    private enum Tab: String, CaseIterable, Identifiable {
        case events = "Мероприятия"
        case people = "Люди"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .events
    @State private var chats: [Chat] = []
    @State private var people: [User] = []
    @State private var query = ""
    @State private var isLoading = true

    private var filteredChats: [Chat] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return chats }
        return chats.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var filteredPeople: [User] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return people }
        return people.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    VStack(spacing: Spacing.s) {
                        Picker("", selection: $tab) {
                            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, Spacing.m)

                        list
                    }
                    .padding(.top, Spacing.s)
                }
            }
            .navigationTitle("Переслать в…")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query,
                        prompt: tab == .events ? "Поиск мероприятия" : "Поиск человека")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } } }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                if tab == .events {
                    ForEach(filteredChats) { chat in
                        Button { pick(.chat(chat)) } label: { ChatRow(chat: chat) }
                            .buttonStyle(PressableStyle())
                    }
                    if filteredChats.isEmpty { nothingFound }
                } else {
                    ForEach(filteredPeople) { person in
                        Button { pick(.person(person)) } label: { personRow(person) }
                            .buttonStyle(PressableStyle())
                    }
                    if filteredPeople.isEmpty { nothingFound }
                }
            }
            .padding(Spacing.m)
        }
    }

    private var nothingFound: some View {
        Text("Никого не нашли").font(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.m)
    }

    private func personRow(_ person: User) -> some View {
        HStack(spacing: Spacing.s) {
            Avatar(name: person.fullName, size: 40, id: person.id)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.fullName).font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                if !person.position.isEmpty {
                    Text(person.position).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "paperplane").font(.caption).foregroundStyle(Theme.accent)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        .contentShape(Rectangle())
    }

    private func pick(_ target: ForwardTarget) {
        onPick(target)
        dismiss()
    }

    private func load() async {
        guard let user = session.currentUser else { isLoading = false; return }
        async let events = session.chats.fetchChats(for: user)
        async let colleagues = DirectoryCache.colleagues()
        let (ev, all) = await (events, colleagues)
        chats = ev
        // Себя из списка убираем: пересылать самому себе некуда.
        people = all.filter { $0.id != user.id }
        isLoading = false
    }
}
