import SwiftUI

/// Выбор чата (мероприятие или ЛС) для пересылки сообщения.
struct ForwardPickerView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let onPick: (Chat) -> Void

    @State private var chats: [Chat] = []
    @State private var query = ""

    private var filtered: [Chat] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return chats }
        return chats.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if chats.isEmpty {
                    ProgressView().tint(Theme.accent)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(filtered) { chat in
                                Button {
                                    onPick(chat)
                                    dismiss()
                                } label: { ChatRow(chat: chat) }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(Spacing.m)
                    }
                }
            }
            .navigationTitle("Переслать в…")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Поиск чата")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        guard let user = session.currentUser else { return }
        async let events = session.chats.fetchChats(for: user)
        async let dms = session.chats.fetchDMChats(for: user)
        let (ev, dm) = await (events, dms)
        chats = ev + dm
    }
}
