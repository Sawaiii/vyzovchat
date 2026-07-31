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
    @State private var isAdmin = false
    @State private var email = ""
    /// Ссылка на текущее фото; ключ нового — отдельно, его ждёт сервер.
    @State private var avatarURL: URL?
    @State private var newAvatarKey: String?
    @State private var localPreview: UIImage?
    @State private var avatarPick: PhotosPickerItem?
    @State private var uploading = false

    @State private var saving = false
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

                        GlassCard {
                            Toggle(isOn: $isAdmin) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Администратор").foregroundStyle(Theme.textPrimary)
                                    Text("Полные права: мероприятия, участники, сотрудники")
                                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                                }
                            }.tint(Theme.accent)
                        }

                        if !isNew { companyAccessCard }

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
        isAdmin = worker.isAdmin
        email = worker.email ?? ""
        avatarURL = worker.avatarURL
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
                patch.is_admin = isAdmin
                patch.phone = phone
                patch.email = email
                if !pass.isEmpty { patch.pass = pass }
                if let newAvatarKey { patch.avatar = newAvatarKey }
                _ = try await session.directory.updateWorker(id: worker.id, patch)
                CompanyAccessStore.setHidden(hiddenCompanies, for: worker.id)
            } else {
                _ = try await session.directory.createWorker(CreateWorkerRequest(
                    fio: fioT, login: loginT, pass: pass, role: nil,
                    is_admin: isAdmin, is_leader: false,
                    email: email.isEmpty ? nil : email,
                    phone: phone.isEmpty ? nil : phone))
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
