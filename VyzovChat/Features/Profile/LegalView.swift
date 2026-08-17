import SwiftUI

/// Адрес, куда пишут по вопросам аккаунта и жалоб.
///
/// Отдельной константой: он нужен и в правилах, и на экране удаления аккаунта,
/// и его же указывают в карточке приложения в App Store — разъезжаться этим
/// трём местам нельзя.
enum SupportContact {
    static let email = "support@vyzovchat.ru"
    static let site = URL(string: "https://vyzovchat.ru")!
}

/// Правила использования и обработка данных.
///
/// Экран обязателен для App Store: в приложении есть переписка и чужие фото,
/// а значит Apple требует показать правила, где прямо сказано, что
/// оскорбительный контент не терпится, и назван способ на него пожаловаться
/// (Guideline 1.2). Текст держим внутри приложения, а не ссылкой на сайт:
/// ссылка требует, чтобы страница жила вечно, и ломается без сети.
struct LegalView: View {
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        section("Что это за приложение", [
                            "Vyzov Chat — рабочий инструмент компании: чаты мероприятий, смены, фотоотчёты и общий диск. Доступ выдаёт администратор компании; без учётной записи приложение не работает."
                        ])

                        section("Правила поведения", [
                            "Приложением пользуются коллеги. Оскорбления, угрозы, травля, откровенный и незаконный контент запрещены полностью — без предупреждений и вторых шансов.",
                            "Загружая фото, видео и файлы, вы отвечаете за то, что имеете право их публиковать и что на них нет посторонних людей, снятых без их согласия.",
                            "Нарушение — основание закрыть доступ к приложению."
                        ])

                        section("Если кто-то нарушает", [
                            "Пожаловаться: откройте состав участников мероприятия, задержите палец на человеке и выберите «Пожаловаться». Жалоба уходит организатору мероприятия, её разбирают.",
                            "Заблокировать: там же — «Заблокировать». Сообщения и файлы этого человека сразу перестанут вам показываться. Снять блокировку можно в профиле, раздел «Заблокированные».",
                            "Жалобы на недопустимый контент рассматриваются в течение 24 часов; по итогам разбора нарушителя удаляют из мероприятия или из системы."
                        ])

                        section("Какие данные собираются", [
                            "Учётная запись: ФИО, должность, логин, телефон, почта для восстановления пароля.",
                            "Содержимое работы: сообщения, голосовые, фото и файлы, которые вы отправляете.",
                            "Смены: отметки прихода и ухода, а также геометка фотографии — она подтверждает место съёмки. Геолокация запрашивается отдельно и только в момент съёмки.",
                            "Данные хранятся на сервере компании и не передаются третьим лицам, не используются для рекламы и не отслеживают вас между приложениями."
                        ])

                        section("Ваши права", [
                            "Вы можете удалить свою учётную запись прямо в приложении: Профиль → «Удалить аккаунт».",
                            "Вопросы по данным и жалобам: \(SupportContact.email)."
                        ])

                        Link("vyzovchat.ru", destination: SupportContact.site)
                            .font(Typography.callout)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, Spacing.m)
                }
            }
            .navigationTitle("Правила и данные")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
            }
        }
    }

    private func section(_ title: String, _ paragraphs: [String]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(paragraphs, id: \.self) { text in
                    Text(text)
                        .font(Typography.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Кого я скрыл от себя. Нужен, чтобы блокировку можно было снять: без этого
/// экрана заблокированный человек исчезает вместе со способом его вернуть.
struct BlockedUsersView: View {
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss
    @State private var blocked: [String: String] = BlockStore.blockedNames

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if blocked.isEmpty {
                    EmptyState(icon: "hand.raised.slash",
                               title: "Никто не заблокирован",
                               message: "Заблокировать человека можно в составе участников мероприятия — задержите на нём палец.")
                } else {
                    ScrollView {
                        VStack(spacing: Spacing.xs) {
                            ForEach(blocked.sorted(by: { $0.value < $1.value }), id: \.key) { id, name in
                                HStack(spacing: Spacing.s) {
                                    Avatar(name: name, size: 40, id: id)
                                    Text(name)
                                        .font(Typography.callout)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button("Разблокировать") {
                                        BlockStore.unblock(id)
                                        withAnimation(.smooth(duration: 0.2)) { blocked = BlockStore.blockedNames }
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                }
                                .padding(Spacing.s)
                                .glass(cornerRadius: Theme.cornerMedium)
                            }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle("Заблокированные")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
            }
        }
    }
}

/// Удаление собственной учётной записи.
///
/// Требование App Store 5.1.1(v): если аккаунт можно завести в приложении (а у
/// нас можно — по коду приглашения), то и удалить его должно быть можно оттуда
/// же, а не письмом в поддержку.
struct DeleteAccountView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    @State private var confirm = false
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Что будет удалено")
                                    .font(Typography.headline).foregroundStyle(Theme.textPrimary)
                                bullet("Учётная запись: ФИО, логин, телефон, почта, аватар.")
                                bullet("Привязка Яндекса, если она есть.")
                                bullet("Участие в мероприятиях и ваши смены.")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Что останется")
                                    .font(Typography.headline).foregroundStyle(Theme.textPrimary)
                                // Честно предупреждаем заранее: рабочая переписка
                                // и отчёты — документы компании, и стереть их по
                                // заявлению одного участника нельзя.
                                bullet("Отправленные сообщения, фотоотчёты и файлы: это рабочие документы мероприятия, они принадлежат компании. Ваше имя в них заменяется на «Удалённый сотрудник».")
                                bullet("Записи в журнале действий — их требует учёт.")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("Отменить удаление нельзя. Вход по этому логину перестанет работать сразу.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)

                        if let errorText { ErrorBanner(text: errorText) }

                        Button {
                            confirm = true
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(Theme.danger) }
                                Text("Удалить аккаунт")
                            }
                            .font(Typography.button)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .glass(cornerRadius: 27, elevated: false)
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(busy)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, Spacing.m)
                }
            }
            .navigationTitle("Удаление аккаунта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
            }
            .confirmationDialog("Удалить аккаунт безвозвратно?",
                                isPresented: $confirm, titleVisibility: .visible) {
                Button("Удалить аккаунт", role: .destructive) { Task { await deleteAccount() } }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(Typography.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func deleteAccount() async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            _ = try await APIClient.shared.delete("/api/me", as: OKDTO.self)
            // Выход после удаления — сам по себе: токен на сервере уже недействителен,
            // и оставаться на экране профиля не с чем.
            await session.signOut()
            dismiss()
        } catch {
            errorText = "Удалить аккаунт не получилось: \(error.localizedDescription). Напишите на \(SupportContact.email)."
        }
    }
}
