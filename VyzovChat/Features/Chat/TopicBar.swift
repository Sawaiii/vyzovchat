import SwiftUI

/// Полоса тем (подканалов) мероприятия: «Общий» + темы, с бейджами непрочитанного.
/// Ведёт себя как переключатель «Мероприятия — Личные — Архив»: синяя капсула
/// перетекает к выбранной теме, выбор синхронен со свайпами ленты.
/// Админ чата может добавить тему кнопкой «+» и удалить долгим нажатием.
struct TopicBar: View {
    let topics: [TopicDTO]
    let selected: Int?
    let canManage: Bool
    let unread: (Int?) -> Int
    let onSelect: (Int?) -> Void
    let onCreate: () -> Void
    let onEditAccess: (TopicDTO) -> Void
    let onDelete: (TopicDTO) -> Void

    @Namespace private var topicPill

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 4) {
                    chip(title: "Общий", id: nil)

                    ForEach(topics) { topic in
                        chip(title: topic.name, id: topic.id, isPrivate: topic.isPrivate)
                            .contextMenu {
                                if canManage {
                                    Button { onEditAccess(topic) } label: {
                                        Label("Кому видна", systemImage: "lock")
                                    }
                                    Button(role: .destructive) { onDelete(topic) } label: {
                                        Label("Удалить тему", systemImage: "trash")
                                    }
                                }
                            }
                    }

                    if canManage {
                        Button(action: onCreate) {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Theme.panel2, in: Capsule())
                // Анимируем здесь: тему меняют и тапом, и свайпом ленты.
                .animation(.smooth(duration: 0.25), value: selected)
                // Тему могли выбрать свайпом ленты — подтягиваем её в видимую часть.
                .onChange(of: selected) {
                    withAnimation(.smooth(duration: 0.25)) {
                        proxy.scrollTo(chipId(selected), anchor: .center)
                    }
                }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Theme.panel.opacity(0.6))
    }

    private func chipId(_ id: Int?) -> String { id.map(String.init) ?? "main" }

    private func chip(title: String, id: Int?, isPrivate: Bool = false) -> some View {
        let isSelected = selected == id
        let count = unread(id)
        return Button { onSelect(id) } label: {
            HStack(spacing: 5) {
                // Замочек: тема видна не всему составу — это важно понимать
                // до того, как что-то в неё написал.
                if isPrivate {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if count > 0 {
                    UnreadBadge(count: count,
                                background: isSelected ? Color.white.opacity(0.3) : Theme.accent)
                }
            }
            .foregroundStyle(isSelected ? Theme.textOnAccent : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            // Капсула «перетекает» между темами, а не перерисовывается.
            .background {
                if isSelected {
                    Capsule().fill(Theme.accent)
                        .matchedGeometryEffect(id: "topicPill", in: topicPill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .id(chipId(id))
    }
}
