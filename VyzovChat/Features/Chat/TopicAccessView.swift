import SwiftUI

/// Кому видна подтема. Приватную тему видят только выбранные роли и люди
/// (плюс админы чата — им сервер открывает всё независимо от настроек).
struct TopicAccessView: View {
    /// nil — создаём новую тему, иначе правим доступ существующей.
    let topic: TopicDTO?
    let dealId: String
    let members: [User]
    let onSaved: () -> Void

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var name = ""
    @State private var isPrivate = false
    @State private var roles: Set<String> = []
    @State private var picked: Set<Int> = []
    @State private var saving = false
    @State private var errorText: String?

    /// Роли в составе мероприятия — их же понимает сервер. Порядок от младшей
    /// к старшей: так список читается как лестница доступа.
    private static let allRoles: [(String, String)] = [
        ("observer", "Наблюдатели"),
        ("member", "Участники"),
        ("storekeeper", "Кладовщики"),
        ("senior", "Старшие"),
        ("admin", "Админы чата")
    ]

    private var isNew: Bool { topic == nil }
    private var canSave: Bool { !saving && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        GlassCard {
                            GlassField(placeholder: "Название темы", icon: "number", text: $name)
                        }
                        .disabled(!isNew)   // сервер меняет только доступ, не название

                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Toggle(isOn: $isPrivate) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Приватная тема").foregroundStyle(Theme.textPrimary)
                                        Text("Видна только выбранным")
                                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .tint(Theme.accent)

                                if isPrivate {
                                    Text("По ролям").font(Typography.caption).foregroundStyle(Theme.textSecondary)
                                    ForEach(Self.allRoles, id: \.0) { role, title in
                                        Toggle(isOn: Binding(
                                            get: { roles.contains(role) },
                                            set: { on in if on { roles.insert(role) } else { roles.remove(role) } }
                                        )) {
                                            Text(title).font(Typography.callout).foregroundStyle(Theme.textPrimary)
                                        }
                                        .tint(Theme.accent)
                                    }
                                }
                            }
                        }

                        if isPrivate {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Поимённо").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                                Text("Админ чата видит тему в любом случае — его отмечать не нужно.")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                                ForEach(members) { member in
                                    let id = Int(member.id) ?? 0
                                    Button {
                                        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
                                        Haptics.selection()
                                    } label: {
                                        HStack(spacing: Spacing.s) {
                                            Image(systemName: picked.contains(id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(picked.contains(id) ? Theme.accent : Theme.textSecondary)
                                            Avatar(name: member.fullName, size: 30, id: member.id)
                                            Text(member.fullName).font(Typography.callout)
                                                .foregroundStyle(Theme.textPrimary).lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(Spacing.s)
                                        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if let errorText { ErrorBanner(text: errorText) }
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, Spacing.s)
                }
            }
            .navigationTitle(isNew ? "Новая тема" : "Доступ к теме")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { Task { await save() } }.disabled(!canSave).bold()
                }
            }
            .task { await prefill() }
        }
    }

    private func prefill() async {
        guard let topic else { return }
        name = topic.name
        // Настройки доступа отдаёт отдельный запрос: в списке тем их нет.
        guard let access = try? await APIClient.shared.get("/api/topics/\(topic.id)/access",
                                                            as: TopicAccessDTO.self) else { return }
        isPrivate = access.visibility == "custom"
        roles = Set(access.roles ?? [])
        picked = Set(access.members ?? [])
    }

    private func save() async {
        saving = true
        errorText = nil
        defer { saving = false }
        let visibility = isPrivate ? "custom" : "all"
        do {
            if let topic {
                struct AccessBody: Encodable {
                    let visibility: String
                    let roles: [String]
                    let members: [Int]
                }
                _ = try await APIClient.shared.patch(
                    "/api/topics/\(topic.id)/access",
                    json: AccessBody(visibility: visibility, roles: Array(roles), members: Array(picked)),
                    as: OKDTO.self)
            } else {
                _ = try await APIClient.shared.post(
                    "/api/events/\(dealId)/topics",
                    json: CreateTopicRequest(name: name.trimmingCharacters(in: .whitespaces),
                                             visibility: visibility,
                                             roles: Array(roles),
                                             members: Array(picked)),
                    as: TopicDTO.self)
            }
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }
}
