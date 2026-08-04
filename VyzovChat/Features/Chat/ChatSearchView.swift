import SwiftUI

/// Поиск по чату — отдельным окном.
///
/// Раньше поиск подменял саму ленту: найденное показывалось вместо переписки,
/// сообщения превращались в ссылки, а после перехода лента возвращалась
/// обратно. Здесь чат остаётся чатом, а найденное живёт в своём окне: выбрал
/// сообщение — окно закрылось, и чат открылся ровно на нём.
struct ChatSearchView: View {
    @ObservedObject var model: ChatViewModel
    /// Что делать с выбранным: закрыть окно и увести ленту к сообщению.
    let onPick: (Message) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics
    @FocusState private var focused: Bool

    private var query: String { model.search.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: 0) {
                    field
                    content
                }
            }
            .navigationTitle("Поиск в чате")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { close() }
                }
            }
        }
        // Клавиатура сразу: окно открывают, чтобы набрать запрос, а не
        // посмотреть на пустой список.
        .onAppear { focused = true }
    }

    private var field: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
            TextField("Слово или фраза", text: $model.search)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !model.search.isEmpty {
                Button { model.search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
        .background(Theme.panel2, in: Capsule())
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder
    private var content: some View {
        // Сервер отвечает пустым списком на запрос короче двух символов —
        // об этом честнее сказать, чем показывать «ничего не найдено».
        if query.count < 2 {
            hint("Введите хотя бы два символа", icon: "text.magnifyingglass")
        } else if model.isSearching && model.searchResults.isEmpty {
            Spacer()
            ProgressView().tint(Theme.accent)
            Spacer()
        } else if model.searchResults.isEmpty {
            hint("Ничего не найдено", icon: "magnifyingglass")
        } else {
            List(model.searchResults) { message in
                Button { pick(message) } label: { row(message) }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.white.opacity(0.06))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func row(_ message: Message) -> some View {
        HStack(spacing: Spacing.s) {
            Avatar(name: message.senderName ?? "?", size: 36, id: message.senderId)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.senderName ?? "Сообщение")
                        .font(Typography.callout).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    Text(RelativeDate.short(message.sentAt))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Text(message.previewText)
                    .font(Typography.subheadline).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                // В каком месте чата лежит найденное: у мероприятия тем бывает
                // с полдесятка, и без подписи непонятно, куда перейдём.
                if let topic = model.topicName(message.topicId) {
                    Text(topic).font(.caption2).foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func hint(_ text: String, icon: String) -> some View {
        VStack(spacing: Spacing.s) {
            Spacer()
            Image(systemName: icon).font(.largeTitle).foregroundStyle(Theme.textSecondary)
            Text(text).font(Typography.callout).foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func pick(_ message: Message) {
        focused = false
        dismiss()
        onPick(message)
    }

    private func close() {
        focused = false
        model.search = ""
        dismiss()
    }
}
