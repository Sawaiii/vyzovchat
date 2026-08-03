import SwiftUI

/// Претензии по мероприятию: что утеряно или повреждено.
///
/// Позиция выбирается из оборудования мероприятия, а не пишется руками — так
/// формулировки совпадают с тем, что реально выдавали со склада.
///
/// Когда претензия зафиксирована, сервер сам заводит подтему «Претензия» — там
/// её и обсуждают. Закрытие с комментарием отправляет этот комментарий туда же.
struct ClaimsView: View {
    let dealId: String
    let isChatAdmin: Bool
    /// Куда написать комментарий при закрытии — тема «Претензия».
    let claimTopicId: Int?

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var claims: [ClaimDTO] = []
    @State private var equipment: [EquipmentDTO] = []
    @State private var rows: [Row] = [Row()]
    @State private var isLoading = true
    @State private var saving = false
    @State private var errorText: String?

    // Закрытие с комментарием
    @State private var closing: ClaimDTO?
    @State private var closeComment = ""

    struct Row: Identifiable {
        let id = UUID()
        var position = ""
        var qty = ""
        var kind = "damage"
        var note = ""
    }

    private var canSave: Bool {
        !saving && rows.contains { !$0.position.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            if let errorText { ErrorBanner(text: errorText) }
                            existing
                            if isChatAdmin { editor }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle("Претензии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .alert("Урегулировать претензию", isPresented: Binding(
                get: { closing != nil }, set: { if !$0 { closing = nil } })
            ) {
                TextField("Комментарий", text: $closeComment)
                Button("Урегулировать") { Task { await close() } }
                Button("Отмена", role: .cancel) { closing = nil; closeComment = "" }
            } message: {
                Text("Комментарий уйдёт в подтему «Претензия», чтобы решение осталось в чате.")
            }
        }
    }

    // MARK: - Уже зафиксированные

    private var existing: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if claims.isEmpty {
                Text("Претензий нет.").font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(claims) { claim in
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text(claim.statusTitle)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(claim.isOpen ? Theme.textOnAccent : Theme.textPrimary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(claim.isOpen ? Theme.danger : Theme.panel2, in: Capsule())
                            Spacer()
                            if isChatAdmin {
                                Button { Task { await remove(claim) } } label: {
                                    Image(systemName: "trash").foregroundStyle(Theme.danger)
                                }
                            }
                        }
                        ForEach(claim.items ?? []) { item in
                            Text(itemLine(item))
                                .font(Typography.callout).foregroundStyle(Theme.textPrimary)
                        }
                        if let author = claim.author_fio, !author.isEmpty {
                            Text(author + (claim.author_role.map { " · \($0)" } ?? ""))
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        if isChatAdmin && claim.isOpen {
                            // Открытая претензия не даёт завершить мероприятие,
                            // поэтому её надо явно урегулировать.
                            Button("Урегулирована") { closing = claim; closeComment = "" }
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
    }

    private func itemLine(_ item: ClaimItemDTO) -> String {
        var line = item.position
        if let qty = item.qty { line += " · \(qty) шт" }
        line += " — " + (item.kind == "loss" ? "утеря" : "ущерб")
        if let note = item.note, !note.isEmpty { line += " (\(note))" }
        return line
    }

    // MARK: - Новая претензия

    private var editor: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Новая претензия").font(Typography.headline).foregroundStyle(Theme.textPrimary)

            ForEach($rows) { $row in
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        // Позицию пишем руками, а список оборудования — быстрый
                        // выбор рядом. Раньше выбрать можно было только из него,
                        // и претензию было не завести вовсе, пока оборудование не
                        // заведено, — хотя побиться может что угодно.
                        HStack(spacing: Spacing.xs) {
                            TextField("Что повреждено или утеряно", text: $row.position)
                                .padding(.horizontal, Spacing.s).padding(.vertical, 10)
                                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))

                            if !equipment.isEmpty {
                                Menu {
                                    ForEach(equipment) { item in
                                        Button(item.name) { row.position = item.name }
                                    }
                                } label: {
                                    Image(systemName: "list.bullet")
                                        .font(.callout).foregroundStyle(Theme.accent)
                                        .frame(width: 40, height: 40)
                                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
                                }
                            }
                        }

                        HStack(spacing: Spacing.xs) {
                            TextField("шт", text: $row.qty)
                                .keyboardType(.numberPad)
                                .frame(width: 60)
                                .padding(.horizontal, Spacing.s).padding(.vertical, 10)
                                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))

                            Picker("", selection: $row.kind) {
                                Text("ущерб").tag("damage")
                                Text("утеря").tag("loss")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)

                            if rows.count > 1 {
                                Button { rows.removeAll { $0.id == row.id } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
                                }
                            }
                        }

                        GlassField(placeholder: "Комментарий", icon: "text.alignleft", text: $row.note)
                    }
                }
            }

            SecondaryButton(title: "Добавить позицию", icon: "plus") { rows.append(Row()) }

            PrimaryButton(title: "Зафиксировать претензию", isLoading: saving, isEnabled: canSave) {
                Task { await save() }
            }
        }
    }

    // MARK: - Действия

    private func save() async {
        saving = true
        errorText = nil
        defer { saving = false }
        let items = rows.compactMap { row -> CreateClaimRequest.Item? in
            let position = row.position.trimmingCharacters(in: .whitespaces)
            guard !position.isEmpty else { return nil }
            return CreateClaimRequest.Item(position: position, kind: row.kind,
                                           note: row.note.trimmingCharacters(in: .whitespaces),
                                           qty: Int(row.qty))
        }
        guard !items.isEmpty else { return }
        do {
            try await session.eventInfo.createClaim(dealId: dealId, items: items)
            rows = [Row()]
            Haptics.success()
            await load()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    /// Закрыть претензию и оставить решение в чате.
    ///
    /// Сервер комментарий при закрытии не принимает, поэтому пишем его отдельным
    /// сообщением в подтему «Претензия» — иначе решение нигде бы не осталось.
    private func close() async {
        guard let claim = closing else { return }
        let comment = closeComment.trimmingCharacters(in: .whitespaces)
        closing = nil
        closeComment = ""
        do {
            try await session.eventInfo.closeClaim(id: claim.id)
            if !comment.isEmpty {
                RealtimeService.shared.sendText("Претензия урегулирована: " + comment,
                                                eventId: dealId, topicId: claimTopicId)
            }
            Haptics.success()
            await load()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func remove(_ claim: ClaimDTO) async {
        do {
            try await session.eventInfo.deleteClaim(id: claim.id)
            Haptics.success()
            await load()
        } catch { errorText = error.localizedDescription }
    }

    private func load() async {
        async let c = session.eventInfo.claims(dealId: dealId)
        async let e = session.eventInfo.equipment(dealId: dealId)
        let (loadedClaims, loadedEquipment) = await (c, e)
        claims = loadedClaims
        equipment = loadedEquipment
        isLoading = false
    }
}
