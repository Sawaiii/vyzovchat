import SwiftUI

/// Создание мероприятия админом: название, компания, даты и состав
/// с отметкой, кто админ чата.
struct CreateEventView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    @State private var name = ""
    @State private var hasStart = false
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date()

    @State private var workers: [User] = []
    @State private var query = ""
    @State private var selected: Set<String> = []
    @State private var admins: Set<String> = []
    @State private var companyId: Int?

    @State private var submitting = false
    @State private var errorText: String?

    private var filteredWorkers: [User] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return workers }
        return workers.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
    }

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !submitting }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        GlassCard {
                            GlassField(placeholder: "Название мероприятия", icon: "briefcase.fill", text: $name)
                        }
                        CompanyPicker(selection: $companyId)
                        GlassCard {
                            VStack(spacing: Spacing.s) {
                                Toggle(isOn: $hasStart) { Text("Начало").foregroundStyle(Theme.textPrimary) }.tint(Theme.accent)
                                if hasStart {
                                    DatePicker("", selection: $startDate).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Toggle(isOn: $hasEnd) { Text("Конец").foregroundStyle(Theme.textPrimary) }.tint(Theme.accent)
                                if hasEnd {
                                    DatePicker("", selection: $endDate).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        Text("Назначить выездников").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                        GlassField(placeholder: "Поиск выездника", icon: "magnifyingglass", text: $query)

                        VStack(spacing: Spacing.xs) {
                            ForEach(filteredWorkers) { worker in workerRow(worker) }
                        }

                        if let errorText { ErrorBanner(text: errorText) }
                    }
                    .padding(Spacing.m)
                }
            }
            .navigationTitle("Новое мероприятие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Создать") { Task { await create() } }.disabled(!canCreate).bold()
                }
            }
            .task { workers = await session.directory.fetchColleagues() }
        }
    }

    private func workerRow(_ worker: User) -> some View {
        let isSel = selected.contains(worker.id)
        return VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSel ? Theme.accent : Theme.textSecondary)
                Avatar(name: worker.fullName, size: 36, id: worker.id)
                VStack(alignment: .leading, spacing: 1) {
                    Text(worker.fullName).font(Typography.callout).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if !worker.position.isEmpty {
                        Text(worker.position).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSel { selected.remove(worker.id); admins.remove(worker.id) }
                else { selected.insert(worker.id) }
            }

            if isSel {
                HStack(spacing: Spacing.s) {
                    Toggle(isOn: Binding(
                        get: { admins.contains(worker.id) },
                        set: { on in if on { admins.insert(worker.id) } else { admins.remove(worker.id) } }
                    )) { Text("Админ чата").font(.caption).foregroundStyle(Theme.textSecondary) }
                    .tint(Theme.accent)
                }
                // Свободного текста роли сервер не принимает: роль в составе —
                // это member / admin / manager / warehouse, задаётся отдельно.
            }
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private func create() async {
        submitting = true
        errorText = nil
        let req = CreateEventRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            company_id: companyId,
            starts_at: hasStart ? DateParse.string(startDate) : nil,
            ends_at: hasEnd ? DateParse.string(endDate) : nil,
            worker_ids: selected.compactMap { Int($0) },
            admin_worker_ids: admins.compactMap { Int($0) }
        )
        do {
            _ = try await session.directory.createEvent(req)
            Haptics.success()
            onCreated()
            dismiss()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
        submitting = false
    }
}
