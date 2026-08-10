import SwiftUI
import PhotosUI

/// Создание/редактирование сотрудника — только глобальный админ.
struct WorkerEditView: View {
    let worker: User?              // nil — создаём нового
    let onSaved: () -> Void

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var fio = ""
    @State private var login = ""
    @State private var pass = ""
    @State private var phone = ""
    @State private var position = ""
    /// Роль в системе. Именно она даёт права: отдельной галочки «администратор»
    /// на сервере больше нет (миграция 00044) — присланный `is_admin` он игнорирует.
    @State private var role: SystemRole = .worker
    /// Куратор «галочкой» — право звать подрядчиков при любой другой роли.
    @State private var isCurator = false
    /// Основная компания.
    @State private var companyId: Int?
    /// Набор компаний реализатора: одной ему мало — в CRM она проставлена не у всех.
    @State private var companyIds: Set<Int> = []
    /// Уволен: пропадает из списков и не может войти, история остаётся.
    @State private var archived = false
    @State private var email = ""
    /// Ссылка на текущее фото; ключ нового — отдельно, его ждёт сервер.
    @State private var avatarURL: URL?
    @State private var newAvatarKey: String?
    @State private var localPreview: UIImage?
    @State private var avatarPick: PhotosPickerItem?
    @State private var uploading = false

    @State private var saving = false
    @State private var deleting = false
    @State private var errorText: String?
    @State private var companies: [CompanyDTO] = []
    @State private var hiddenCompanies: Set<String> = []

    private var isNew: Bool { worker == nil }
    private var canSave: Bool {
        !fio.trimmingCharacters(in: .whitespaces).isEmpty
            && !login.trimmingCharacters(in: .whitespaces).isEmpty
            && (!isNew || pass.count >= 4)
            && !saving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        avatarPicker

                        GlassCard {
                            VStack(spacing: Spacing.s) {
                                GlassField(placeholder: "ФИО", icon: "person.fill", text: $fio)
                                GlassField(placeholder: "Логин", icon: "at", text: $login)
                                GlassField(placeholder: isNew ? "Пароль (от 4 символов)" : "Новый пароль (необязательно)",
                                           icon: "lock.fill", isSecure: true, text: $pass)
                                GlassField(placeholder: "Телефон", icon: "phone.fill",
                                           keyboard: .phonePad, text: $phone)
                                GlassField(placeholder: "Должность / специализация",
                                           icon: "briefcase.fill", text: $position)
                            }
                        }

                        roleCard

                        CompanyPicker(selection: $companyId)

                        if role.needsCompany && !isNew { companiesCard }

                        if !isNew { companyAccessCard }

                        if !isNew && worker?.id != session.currentUser?.id { dismissCard }

                        if let errorText { ErrorBanner(text: errorText) }
                    }
                    .padding(Spacing.m)
                }
            }
            .navigationTitle(isNew ? "Новый сотрудник" : "Сотрудник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { Task { await save() } }.disabled(!canSave).bold()
                }
            }
            .onAppear(perform: prefill)
        }
    }

    /// Роль в системе. Одним списком, а не набором галочек: сервер считает права
    /// ровно от неё, и две сущности («роль» + «полные права») уже разъезжались.
    private var roleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Роль в системе").font(Typography.headline).foregroundStyle(Theme.textPrimary)

                ForEach(SystemRole.allCases) { item in
                    Button {
                        role = item
                        Haptics.tap()
                    } label: {
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Image(systemName: role == item ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(role == item ? Theme.accent : Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(Typography.callout)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(item.hint).font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(Theme.textSecondary.opacity(0.2))

                // Куратор бывает и «галочкой» при другой роли — сервер это различает
                // (is_curator рядом с role), и теги для кураторов видны обоим.
                Toggle(isOn: $isCurator) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Может звать подрядчиков").foregroundStyle(Theme.textPrimary)
                        Text("Ссылка-приглашение в мероприятия, где сам состоит")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
                .disabled(role == .curator)
            }
        }
    }

    /// Какие компании ведёт реализатор. Набором, а не одной: у большинства
    /// мероприятий компания в CRM не проставлена, а вести можно несколько.
    private var companiesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Ведёт компании").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                ForEach(companies) { company in
                    Toggle(isOn: Binding(
                        get: { companyIds.contains(company.id) },
                        set: { on in
                            if on { companyIds.insert(company.id) } else { companyIds.remove(company.id) }
                        }
                    )) {
                        CompanyBadge(name: company.name, compact: false)
                    }
                    .tint(Theme.accent)
                }
                Text("Чаты этих компаний он видит целиком и админит их — как свои.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .task { if companies.isEmpty { companies = await session.directory.fetchCompanies() } }
    }

    /// Увольнение и удаление. Обычный путь — «Уволить»: человек пропадает из
    /// списков и не может войти, но его отметки, смены и сообщения остаются на
    /// месте. Удаление насовсем оставлено рядом — для ошибочно заведённых.
    private var dismissCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Toggle(isOn: $archived) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Уволен").foregroundStyle(Theme.textPrimary)
                        Text("Не входит в систему и не показывается в списках")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.danger)

                Button(role: .destructive) { deleting = true } label: {
                    Label("Удалить насовсем", systemImage: "trash")
                        .font(.caption).foregroundStyle(Theme.danger)
                }
                Text("Удаление — для ошибочно заведённых учёток. Уволенного лучше оставить в архиве: за ним история смен и переписки.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .confirmationDialog("Удалить сотрудника?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await remove() } }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// Видимость компаний. Задаток: на сервере поля пока нет, список хранится
    /// на устройстве (см. CompanyAccessStore) и фильтрует вкладку «Заказы».
    private var companyAccessCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Доступ к компаниям").font(Typography.headline).foregroundStyle(Theme.textPrimary)

                ForEach(companies) { company in
                    Toggle(isOn: Binding(
                        get: { !hiddenCompanies.contains(company.name) },
                        set: { visible in
                            if visible { hiddenCompanies.remove(company.name) } else { hiddenCompanies.insert(company.name) }
                        }
                    )) {
                        HStack(spacing: 6) {
                            CompanyBadge(name: company.name, compact: false)
                            Spacer()
                        }
                    }
                    .tint(Theme.accent)
                }

                Text("Выключенные компании сотрудник не видит в заказах. Пока настройка хранится на этом устройстве.")
                    .font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .task {
            companies = await session.directory.fetchCompanies()
            if let id = worker?.id { hiddenCompanies = CompanyAccessStore.hidden(for: id) }
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarPick, matching: .images) {
            VStack(spacing: Spacing.xs) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let localPreview {
                            Image(uiImage: localPreview).resizable().scaledToFill()
                        } else if let url = avatarURL {
                            CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                                Circle().fill(Theme.panel2)
                            }
                        } else {
                            Avatar(name: fio.isEmpty ? "?" : fio, size: 84, id: worker?.id ?? "new")
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())

                    Image(systemName: uploading ? "arrow.triangle.2.circlepath" : "camera.fill")
                        .font(.caption).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
                }
                Text("Фото сотрудника").font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: avatarPick) { uploadAvatar() }
    }

    private func prefill() {
        guard let worker else { return }
        fio = worker.fullName
        login = worker.login
        phone = worker.phone
        position = worker.position
        role = SystemRole(worker.globalRole)
        isCurator = worker.isCurator
        companyId = worker.companyId
        companyIds = Set(worker.companyIds)
        archived = worker.isArchived
        email = worker.email ?? ""
        avatarURL = worker.avatarURL
    }

    private func remove() async {
        guard let worker else { return }
        saving = true
        defer { saving = false }
        do {
            try await session.directory.deleteWorker(id: worker.id)
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func uploadAvatar() {
        guard let avatarPick else { return }
        uploading = true
        Task {
            if let data = try? await avatarPick.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let key = try? await MediaUploader.uploadAvatar(image) {
                newAvatarKey = key
                localPreview = image
            }
            uploading = false
            self.avatarPick = nil
        }
    }

    private func save() async {
        saving = true
        errorText = nil
        let fioT = fio.trimmingCharacters(in: .whitespaces)
        let loginT = login.trimmingCharacters(in: .whitespaces)
        do {
            if let worker {
                // Логин и должность сервер через этот запрос не меняет — только то,
                // что перечислено в UpdateWorkerRequest.
                var patch = UpdateWorkerRequest()
                patch.fio = fioT
                // Права считает сервер от роли; is_admin/is_leader он игнорирует.
                patch.role = role.rawValue
                patch.is_curator = isCurator || role == .curator
                // -1 — отвязать компанию (сервер понимает это именно так).
                patch.company_id = companyId ?? -1
                // Набор компаний имеет смысл только у реализатора; у остальных
                // ролей его чистим, чтобы не оставлять права «про запас».
                patch.company_ids = role.needsCompany ? Array(companyIds) : []
                patch.archived = archived
                patch.phone = phone
                patch.email = email
                if !pass.isEmpty { patch.pass = pass }
                if let newAvatarKey { patch.avatar = newAvatarKey }
                _ = try await session.directory.updateWorker(id: worker.id, patch)
                CompanyAccessStore.setHidden(hiddenCompanies, for: worker.id)
            } else {
                // Компанию сервер принимает сразу; набор компаний реализатора
                // и галочку куратора — только правкой, отдельным запросом.
                let created = try await session.directory.createWorker(CreateWorkerRequest(
                    fio: fioT, login: loginT, pass: pass, role: role.rawValue,
                    is_leader: role == .leader,
                    email: email.isEmpty ? nil : email,
                    phone: phone.isEmpty ? nil : phone,
                    company_id: companyId))
                if isCurator || (role.needsCompany && !companyIds.isEmpty) {
                    var patch = UpdateWorkerRequest()
                    if isCurator { patch.is_curator = true }
                    if role.needsCompany { patch.company_ids = Array(companyIds) }
                    _ = try? await session.directory.updateWorker(id: created.id, patch)
                }
            }
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
        saving = false
    }
}
