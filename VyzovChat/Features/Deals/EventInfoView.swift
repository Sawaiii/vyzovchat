import SwiftUI
import UniformTypeIdentifiers

/// Обвязка мероприятия: оборудование, документы (акты), претензии и приглашение
/// по ссылке. Участник всё это видит, правит — админ чата; звать по ссылке может
/// ещё и куратор.
struct EventInfoView: View {
    let dealId: String
    let eventTitle: String
    let isChatAdmin: Bool
    let canInvite: Bool

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.openURL) private var openURL

    @State private var equipment: [EquipmentDTO] = []
    @State private var documents: [DocumentDTO] = []
    @State private var claims: [ClaimDTO] = []
    @State private var isLoading = true
    @State private var errorText: String?

    // Добавление оборудования
    @State private var newItemName = ""
    @State private var newItemQty = ""

    // Приглашение
    @State private var invite: InviteDTO?
    @State private var invitingRole: String?

    @State private var showClaimEditor = false
    @State private var showFileImporter = false
    @State private var uploadingDoc = false

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
                            if canInvite { inviteCard }
                            claimsSection
                            documentsSection
                            equipmentSection
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle("Мероприятие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showClaimEditor) {
                ClaimEditorView(dealId: dealId) { Task { await load() } }
                    .environmentObject(session)
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
                handleDocumentImport(result)
            }
        }
    }

    // MARK: - Приглашение по ссылке

    private var inviteCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Позвать по ссылке").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                Text("Человек откроет ссылку в браузере, заведёт себе вход и сразу попадёт в это мероприятие. Ссылка одноразовая и живёт неделю.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)

                if let invite, let url = invite.url {
                    ShareLink(item: url) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                            .font(Typography.button).foregroundStyle(Theme.textOnAccent)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Theme.accent, in: Capsule())
                    }
                    Text(url.absoluteString)
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).textSelection(.enabled)
                }

                HStack(spacing: Spacing.xs) {
                    inviteButton(title: "Подрядчик", role: "member")
                    // Менеджера и склад заводит только админ чата: их права шире,
                    // чем у куратора, и сервер понизил бы роль до подрядчика.
                    if isChatAdmin {
                        inviteButton(title: "Менеджер", role: "manager")
                        inviteButton(title: "Склад", role: "warehouse")
                    }
                }
            }
        }
    }

    private func inviteButton(title: String, role: String) -> some View {
        Button {
            Task { await makeInvite(role: role) }
        } label: {
            Group {
                if invitingRole == role { ProgressView().tint(Theme.accent) }
                else { Text(title).font(.caption.weight(.semibold)) }
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity).frame(height: 36)
            .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        }
        .buttonStyle(.plain)
        .disabled(invitingRole != nil)
    }

    private func makeInvite(role: String) async {
        invitingRole = role
        errorText = nil
        defer { invitingRole = nil }
        do {
            invite = try await session.eventInfo.createInvite(dealId: dealId, role: role)
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    // MARK: - Претензии

    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Претензии").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                if isChatAdmin {
                    Button("Зафиксировать") { showClaimEditor = true }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            if claims.isEmpty {
                Text("Претензий нет.").font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(claims) { claim in claimRow(claim) }
        }
    }

    private func claimRow(_ claim: ClaimDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(claim.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(claim.isOpen ? Theme.danger : Theme.success)
                Spacer()
                if let author = claim.author_fio, !author.isEmpty {
                    Text(author).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            ForEach(claim.items ?? []) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.position + (item.qty.map { " — \($0) шт." } ?? ""))
                            .font(Typography.callout).foregroundStyle(Theme.textPrimary)
                        Text(item.kindTitle + (item.note.map { ": \($0)" } ?? ""))
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if isChatAdmin && claim.isOpen {
                // Открытая претензия блокирует завершение и архивацию мероприятия —
                // поэтому её надо явно урегулировать.
                Button("Урегулирована") { Task { await closeClaim(claim) } }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private func closeClaim(_ claim: ClaimDTO) async {
        do {
            try await session.eventInfo.closeClaim(id: claim.id)
            Haptics.success()
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Документы

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Документы").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                if isChatAdmin {
                    Button(uploadingDoc ? "Загрузка…" : "Добавить") { showFileImporter = true }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        .disabled(uploadingDoc)
                }
            }
            if documents.isEmpty {
                Text("Документов нет.").font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(documents) { doc in documentRow(doc) }
        }
    }

    private func documentRow(_ doc: DocumentDTO) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "doc.text.fill").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(doc.typeTitle).font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let name = doc.file_name, !name.isEmpty {
                    Text(name).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                } else if let body = doc.body, !body.isEmpty {
                    Text(body).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer()
            if let link = AppConfig.mediaURL(doc.download_url ?? doc.file_url) {
                Button { openURL(link) } label: {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Theme.accent)
                }
            }
            if isChatAdmin {
                Button { Task { await deleteDocument(doc) } } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.danger)
                }
            }
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private func deleteDocument(_ doc: DocumentDTO) async {
        do {
            try await session.eventInfo.deleteDocument(dealId: dealId, docId: doc.id)
            Haptics.success()
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Документ уходит в хранилище напрямую (presign с purpose «document»),
    /// а на сервер отправляется только выданный ключ.
    private func handleDocumentImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        uploadingDoc = true
        errorText = nil
        Task {
            defer { uploadingDoc = false }
            let access = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            let name = url.lastPathComponent
            if access { url.stopAccessingSecurityScopedResource() }
            guard let data else { return }
            do {
                let media = try await MediaUploader.uploadFile(data, filename: name, purpose: .document)
                _ = try await session.eventInfo.addDocument(dealId: dealId, AddDocumentRequest(
                    type: "other", title: name, key: media.key, name: name, size: media.size, body: nil))
                Haptics.success()
                await load()
            } catch {
                errorText = error.localizedDescription
                Haptics.warning()
            }
        }
    }

    // MARK: - Оборудование

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Оборудование").font(Typography.headline).foregroundStyle(Theme.textPrimary)
            if equipment.isEmpty {
                Text("Список пуст.").font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(equipment) { item in
                HStack(spacing: Spacing.s) {
                    Image(systemName: "shippingbox.fill").foregroundStyle(Theme.groupTitle)
                    Text(item.name).font(Typography.callout)
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    if let qty = item.qty {
                        Text("\(qty) шт.").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    if isChatAdmin {
                        Button { Task { await deleteEquipment(item) } } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.danger)
                        }
                    }
                }
                .padding(Spacing.s)
                .glass(cornerRadius: Theme.cornerSmall, elevated: false)
            }

            if isChatAdmin {
                HStack(spacing: Spacing.xs) {
                    TextField("Позиция", text: $newItemName)
                        .padding(.horizontal, Spacing.s).padding(.vertical, 8)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
                    TextField("Кол-во", text: $newItemQty)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .padding(.horizontal, Spacing.s).padding(.vertical, 8)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
                    Button { Task { await addEquipment() } } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                    }
                    .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addEquipment() async {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let item = try await session.eventInfo.addEquipment(dealId: dealId, name: name, qty: Int(newItemQty))
            equipment.append(item)
            newItemName = ""
            newItemQty = ""
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func deleteEquipment(_ item: EquipmentDTO) async {
        do {
            try await session.eventInfo.deleteEquipment(dealId: dealId, itemId: item.id)
            equipment.removeAll { $0.id == item.id }
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Загрузка

    private func load() async {
        async let eq = session.eventInfo.equipment(dealId: dealId)
        async let docs = session.eventInfo.documents(dealId: dealId)
        async let cl = session.eventInfo.claims(dealId: dealId)
        let (e, d, c) = await (eq, docs, cl)
        equipment = e
        documents = d
        claims = c
        isLoading = false
    }
}

/// Форма претензии: перечень утерянного и повреждённого.
private struct ClaimEditorView: View {
    let dealId: String
    let onSaved: () -> Void

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    struct Row: Identifiable {
        let id = UUID()
        var position = ""
        var kind = "damage"
        var qty = ""
        var note = ""
    }

    @State private var rows: [Row] = [Row()]
    @State private var saving = false
    @State private var errorText: String?

    private var canSave: Bool {
        !saving && rows.contains { !$0.position.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        Text("Перечислите, что утеряно или повреждено. Пока претензия открыта, мероприятие нельзя завершить или убрать в архив.")
                            .font(Typography.caption).foregroundStyle(Theme.textSecondary)

                        ForEach($rows) { $row in
                            GlassCard {
                                VStack(spacing: Spacing.s) {
                                    GlassField(placeholder: "Позиция", icon: "shippingbox", text: $row.position)
                                    Picker("", selection: $row.kind) {
                                        Text("Повреждено").tag("damage")
                                        Text("Утеряно").tag("loss")
                                    }
                                    .pickerStyle(.segmented)
                                    GlassField(placeholder: "Количество", icon: "number", keyboard: .numberPad, text: $row.qty)
                                    GlassField(placeholder: "Примечание", icon: "text.alignleft", text: $row.note)
                                }
                            }
                        }

                        SecondaryButton(title: "Ещё позиция", icon: "plus") { rows.append(Row()) }
                        if let errorText { ErrorBanner(text: errorText) }
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, Spacing.s)
                }
            }
            .navigationTitle("Претензия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { Task { await save() } }.disabled(!canSave).bold()
                }
            }
        }
    }

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
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }
}
