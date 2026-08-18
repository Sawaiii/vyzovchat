import SwiftUI
import PhotosUI

/// Редактирование информации о мероприятии (группе).
/// Доступно только глобальному админу — так же, как на сервере (PATCH /api/events/:id).
struct EditEventView: View {
    let dealId: String
    var onSaved: () -> Void = {}

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hasStart = false
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date()
    @State private var archived = false
    @State private var status = "active"
    /// Что показывать сейчас — подписанная ссылка от сервера.
    @State private var photoURL: URL?
    /// Ключ только что загруженной картинки; nil — картинку не меняли.
    @State private var newAvatarKey: String?
    @State private var colorHex: String?           // цвет-обои чата
    @State private var photoPick: PhotosPickerItem?
    @State private var uploadingPhoto = false
    /// Только что выбранное фото — показать до сохранения.
    @State private var localPreview: UIImage?

    // Метки и признаки мероприятия
    @State private var allTags: [EventTagDTO] = []
    @State private var selectedTagIds: Set<Int> = []
    @State private var needsPhoto = false
    @State private var needsReport = false
    @State private var photosRestricted = false

    @State private var isLoading = true
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmClose = false
    @State private var confirmDelete = false

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            photoPicker

                            GlassCard {
                                GlassField(placeholder: "Название мероприятия",
                                           icon: "briefcase.fill", text: $name)
                            }

                            GlassCard {
                                VStack(spacing: Spacing.s) {
                                    Toggle(isOn: $hasStart) {
                                        Text("Начало").foregroundStyle(Theme.textPrimary)
                                    }.tint(Theme.accent)
                                    if hasStart {
                                        DatePicker("", selection: $startDate).labelsHidden()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Toggle(isOn: $hasEnd) {
                                        Text("Конец").foregroundStyle(Theme.textPrimary)
                                    }.tint(Theme.accent)
                                    if hasEnd {
                                        DatePicker("", selection: $endDate).labelsHidden()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }

                            colorPicker
                            tagsCard

                            GlassCard {
                                Toggle(isOn: $archived) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("В архиве").foregroundStyle(Theme.textPrimary)
                                        Text("Мероприятие уходит в раздел «Архив»")
                                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                }.tint(Theme.accent)
                            }

                            dangerZone

                            if let errorText { ErrorBanner(text: errorText) }
                        }
                        .padding(Spacing.m)
                    }
                }
            }
            .navigationTitle("Изменить мероприятие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { Task { await save() } }.disabled(!canSave).bold()
                }
            }
            .task { await load() }
        }
    }

    /// Цвет-обои чата мероприятия.
    private var colorPicker: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Цвет чата").foregroundStyle(Theme.textPrimary)
                HStack(spacing: Spacing.xs) {
                    ForEach(Self.palette, id: \.self) { hex in
                        Button { colorHex = hex } label: {
                            Circle()
                                .fill(Color(hexString: hex) ?? Theme.panel2)
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().strokeBorder(
                                        colorHex == hex ? Theme.accent : .white.opacity(0.15),
                                        lineWidth: colorHex == hex ? 3 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Button { colorHex = nil } label: {
                        Circle()
                            .fill(Theme.panel2)
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "slash.circle").font(.caption)
                                .foregroundStyle(Theme.textSecondary))
                            .overlay(Circle().strokeBorder(
                                colorHex == nil ? Theme.accent : .white.opacity(0.15),
                                lineWidth: colorHex == nil ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
                Text("Фон чата у всех участников. «Перечёркнуто» — тема по умолчанию.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private static let palette = ["17212B", "1E2C3A", "2B5278", "3D2B4F", "2F4F3A", "4F3B2B", "3A2F2F"]

    /// Метки мероприятия и признаки для списка чатов. Словарь меток заводит
    /// админ организации, здесь их только расставляют.
    private var tagsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Метки").foregroundStyle(Theme.textPrimary)
                if allTags.isEmpty {
                    Text("Словарь меток пуст — его заполняет администратор.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(allTags) { tag in
                            let on = selectedTagIds.contains(tag.id)
                            Button {
                                if on { selectedTagIds.remove(tag.id) } else { selectedTagIds.insert(tag.id) }
                                Haptics.selection()
                            } label: {
                                Text(tag.name)
                                    .font(.caption.weight(on ? .semibold : .regular))
                                    .foregroundStyle(on ? Theme.textOnAccent : Theme.textSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(on ? (Color(hexString: tag.color) ?? Theme.accent) : Theme.panel2,
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().overlay(Theme.line)

                Toggle(isOn: $needsPhoto) {
                    Text("Нужны фото").foregroundStyle(Theme.textPrimary)
                }.tint(Theme.accent)
                Toggle(isOn: $needsReport) {
                    Text("Нужен отчёт").foregroundStyle(Theme.textPrimary)
                }.tint(Theme.accent)
                Toggle(isOn: $photosRestricted) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Фото использовать нельзя").foregroundStyle(Theme.textPrimary)
                        Text("Клиент запретил публикацию — видно в фотобанке и на дашборде")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }.tint(Theme.warning)
            }
        }
    }

    /// Удалить мероприятие может только админ и руководитель (`canDeleteEvent`).
    private var canDelete: Bool {
        SystemRole(session.currentUser?.globalRole).canDeleteEvent
    }

    /// Завершение и удаление мероприятия.
    private var dangerZone: some View {
        VStack(spacing: Spacing.xs) {
            SecondaryButton(title: "Завершить мероприятие", icon: "checkmark.seal") {
                confirmClose = true
            }
            // Удаление — только у админа и руководителя. Реализатору с 14 августа
            // 2026 отдали полные права, но эту кнопку оставили за руководством:
            // мероприятие уходит со всей перепиской, и обратно её не достать.
            if canDelete {
                Button { confirmDelete = true } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "trash")
                        Text("Удалить мероприятие")
                    }
                    .font(Typography.button).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .glass(cornerRadius: 27, elevated: false)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .confirmationDialog("Завершить мероприятие?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Завершить") { Task { await closeEvent() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Чат уйдёт в архив, отправка отчёта станет недоступна.")
        }
        .confirmationDialog("Удалить мероприятие?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await deleteEvent() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут удалены чат и все сообщения. Действие необратимо.")
        }
    }

    /// Завершение — это статус `closed` у мероприятия. Отдельного эндпоинта нет,
    /// шлём тем же PATCH. Незакрытая претензия завершить не даст (`claim_open`).
    private func closeEvent() async {
        status = "closed"
        await save()
    }

    private func deleteEvent() async {
        do {
            try await session.directory.deleteEvent(id: dealId)
            Haptics.success(); onSaved(); dismiss()
        } catch { errorText = error.localizedDescription }
    }

    /// Фото чата мероприятия — задаёт админ.
    private var photoPicker: some View {
        PhotosPicker(selection: $photoPick, matching: .images) {
            VStack(spacing: Spacing.xs) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let localPreview {
                            Image(uiImage: localPreview).resizable().scaledToFill()
                        } else if let url = photoURL {
                            CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                                Circle().fill(Theme.panel2)
                            }
                        } else {
                            Circle().fill(Theme.panel2)
                                .overlay(Image(systemName: "photo").foregroundStyle(Theme.textSecondary))
                        }
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())

                    Image(systemName: uploadingPhoto ? "arrow.triangle.2.circlepath" : "camera.fill")
                        .font(.caption).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
                }
                Text("Фото чата").font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: photoPick) { uploadPhoto() }
    }

    /// Картинку мероприятия сервер ждёт уменьшенной и уже лежащей в хранилище:
    /// грузим её напрямую и запоминаем выданный ключ — он уйдёт в PATCH.
    private func uploadPhoto() {
        guard let photoPick else { return }
        uploadingPhoto = true
        Task {
            if let data = try? await photoPick.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let key = try? await MediaUploader.uploadAvatar(image, purpose: .eventAvatar) {
                newAvatarKey = key
                // До сохранения показываем выбранное фото прямо из памяти:
                // подписанную ссылку сервер отдаст только после PATCH.
                photoURL = nil
                localPreview = image
            }
            uploadingPhoto = false
            self.photoPick = nil
        }
    }

    private func load() async {
        guard let dto = await session.directory.event(id: dealId) else {
            isLoading = false
            errorText = "Не удалось загрузить мероприятие"
            return
        }
        name = dto.name
        if let s = DateParse.iso(dto.starts_at) { hasStart = true; startDate = s }
        if let e = DateParse.iso(dto.ends_at) { hasEnd = true; endDate = e }
        archived = dto.archived ?? false
        status = dto.status ?? "active"
        photoURL = AppConfig.mediaURL(dto.avatar_url)
        colorHex = dto.color
        needsPhoto = dto.needs_photo ?? false
        needsReport = dto.needs_report ?? false
        photosRestricted = dto.photos_restricted ?? false
        selectedTagIds = Set((dto.tags ?? []).map(\.id))
        allTags = await session.directory.tags()
        isLoading = false
    }

    private func save() async {
        saving = true
        errorText = nil
        let req = UpdateEventRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            status: status,
            archived: archived,
            starts_at: hasStart ? DateParse.string(startDate) : nil,
            ends_at: hasEnd ? DateParse.string(endDate) : nil,
            color: colorHex,
            // nil — картинку не трогали; пустая строка означала бы «убрать».
            avatar: newAvatarKey
        )
        do {
            try await session.directory.updateEvent(id: dealId, req)
            // Метки и признаки — отдельный запрос: сервер принимает их не в PATCH.
            try await session.directory.setEventTags(
                dealId: dealId, tagIds: Array(selectedTagIds),
                needsPhoto: needsPhoto, needsReport: needsReport, photosRestricted: photosRestricted)
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            errorText = Self.message(for: error)
            Haptics.warning()
        }
        saving = false
    }

    /// Понятный текст вместо кода ошибки сервера.
    private static func message(for error: Error) -> String {
        guard case let APIError.http(_, code) = error, let code else { return error.localizedDescription }
        switch code {
        case "claim_open":
            return "По мероприятию открыта претензия. Пока она не урегулирована, завершить или убрать в архив нельзя."
        case "chat_admin_only":
            return "Менять мероприятие может только админ этого чата"
        default:
            return error.localizedDescription
        }
    }
}
