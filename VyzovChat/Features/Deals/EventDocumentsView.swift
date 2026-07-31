import SwiftUI

/// Документы мероприятия: акт приёма, акт возврата и прочие.
///
/// Актов по одному каждого вида: пока файла нет — кнопка «Добавить», когда он
/// приложен — «Заменить» (сервер при добавлении затирает предыдущий).
struct EventDocumentsView: View {
    let dealId: String
    let isChatAdmin: Bool

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.openURL) private var openURL

    @State private var documents: [DocumentDTO] = []
    @State private var isLoading = true
    @State private var errorText: String?

    // Форма «прочего» документа
    @State private var title = ""
    @State private var note = ""
    @State private var picked: (data: Data, name: String)?
    @State private var uploading = false

    /// Какой вид документа сейчас выбираем файлом.
    @State private var importingFor: String?

    private func document(of type: String) -> DocumentDTO? {
        documents.first { $0.type == type }
    }
    private var others: [DocumentDTO] {
        documents.filter { $0.type != "act_accept" && $0.type != "act_return" }
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
                            actCard("Акт приёма", type: "act_accept")
                            actCard("Акт возврата", type: "act_return")
                            othersSection
                            if isChatAdmin { addForm }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle("Документы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .fileImporter(isPresented: Binding(get: { importingFor != nil },
                                               set: { if !$0 { importingFor = nil } }),
                          allowedContentTypes: [.item]) { result in
                handleImport(result)
            }
        }
    }

    // MARK: - Акты

    private func actCard(_ name: String, type: String) -> some View {
        let doc = document(of: type)
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text(name).font(Typography.headline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if isChatAdmin {
                        Button(doc == nil ? "Добавить" : "Заменить") { importingFor = type }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textOnAccent)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                if let doc {
                    docRow(doc)
                } else {
                    Text("Не приложен.").font(Typography.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// Строка документа: превью или имя файла, скачать и отметка «в Tony».
    private func docRow(_ doc: DocumentDTO) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                if AppConfig.isImage(doc.file_name), let url = AppConfig.mediaURL(doc.file_url) {
                    CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.panel2 }
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "doc.text.fill").foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let name = doc.file_name, !name.isEmpty {
                        Text(name).font(Typography.callout)
                            .foregroundStyle(Theme.accent).lineLimit(2)
                    }
                    if let body = doc.body, !body.isEmpty {
                        Text(body).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(3)
                    }
                }
                Spacer()
            }

            HStack(spacing: Spacing.s) {
                if let link = AppConfig.mediaURL(doc.download_url ?? doc.file_url) {
                    Button("Скачать") { openURL(link) }
                        .font(.caption).foregroundStyle(Theme.accent)
                }
                // Отметка «ушёл в учётную систему» — её ставит админ чата.
                if doc.sent_to_tony == true {
                    Label("в Tony", systemImage: "checkmark.seal.fill")
                        .font(.caption2).foregroundStyle(Theme.success)
                } else if isChatAdmin {
                    Button("в Tony") { Task { await sendToTony(doc) } }
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Capsule().stroke(Theme.textSecondary.opacity(0.4), lineWidth: 1))
                }
                Spacer()
                if isChatAdmin {
                    Button { Task { await remove(doc) } } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.danger)
                    }
                }
            }
        }
    }

    // MARK: - Прочие

    private var othersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Прочие документы").font(Typography.headline).foregroundStyle(Theme.textPrimary)
            if others.isEmpty {
                Text("Нет.").font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(others) { doc in
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if let t = doc.title, !t.isEmpty {
                            Text(t).font(Typography.callout.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        docRow(doc)
                    }
                }
            }
        }
    }

    private var addForm: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                GlassField(placeholder: "Название документа", icon: "textformat", text: $title)
                GlassField(placeholder: "Заметка (необязательно)", icon: "text.alignleft", text: $note)
                HStack(spacing: Spacing.s) {
                    Button(picked == nil ? "Выбрать файл" : (picked?.name ?? "Файл")) {
                        importingFor = "other"
                    }
                    .font(.caption).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.panel2, in: Capsule())
                    .lineLimit(1)

                    Spacer()

                    Button(uploading ? "Добавляем…" : "Добавить документ") {
                        Task { await addOther() }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textOnAccent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
                    .disabled(uploading || (picked == nil && note.trimmingCharacters(in: .whitespaces).isEmpty))
                }
                // Сервер требует хоть что-то: либо файл, либо текст.
                Text("Нужен файл или заметка — пустой документ сервер не примет.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Действия

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result, let type = importingFor else { return }
        importingFor = nil
        let access = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        let name = url.lastPathComponent
        if access { url.stopAccessingSecurityScopedResource() }
        guard let data else { return }

        if type == "other" {
            picked = (data, name)
            if title.trimmingCharacters(in: .whitespaces).isEmpty { title = name }
        } else {
            Task { await upload(data: data, name: name, type: type, title: nil, note: nil) }
        }
    }

    private func addOther() async {
        let noteText = note.trimmingCharacters(in: .whitespaces)
        await upload(data: picked?.data, name: picked?.name,
                     type: "other",
                     title: title.trimmingCharacters(in: .whitespaces),
                     note: noteText.isEmpty ? nil : noteText)
        title = ""
        note = ""
        picked = nil
    }

    private func upload(data: Data?, name: String?, type: String, title: String?, note: String?) async {
        uploading = true
        errorText = nil
        defer { uploading = false }
        do {
            var key: String?
            var size: Int?
            if let data, let name {
                // Файл идёт в хранилище напрямую, на сервер уходит только ключ.
                let media = try await MediaUploader.uploadFile(data, filename: name, purpose: .document)
                key = media.key
                size = media.size
            }
            _ = try await session.eventInfo.addDocument(dealId: dealId, AddDocumentRequest(
                type: type, title: title, key: key, name: name, size: size, body: note))
            Haptics.success()
            await load()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func sendToTony(_ doc: DocumentDTO) async {
        do {
            try await session.eventInfo.sendDocumentToTony(dealId: dealId, docId: doc.id)
            Haptics.success()
            await load()
        } catch { errorText = error.localizedDescription }
    }

    private func remove(_ doc: DocumentDTO) async {
        do {
            try await session.eventInfo.deleteDocument(dealId: dealId, docId: doc.id)
            Haptics.success()
            await load()
        } catch { errorText = error.localizedDescription }
    }

    private func load() async {
        documents = await session.eventInfo.documents(dealId: dealId)
        isLoading = false
    }
}
