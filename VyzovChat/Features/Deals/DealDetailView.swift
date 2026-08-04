import SwiftUI

struct DealDetailView: View {
    let deal: Deal
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @State private var participants: [User] = []
    @State private var showEdit = false

    /// Чат этого мероприятия — чтобы открыть его прямо из карточки заказа.
    private var chatForDeal: Chat {
        Chat(id: "chat-\(deal.id)", dealId: deal.id, title: deal.title,
             participantIds: deal.assignedUserIds,
             lastMessagePreview: nil, lastMessageDate: deal.eventDate,
             unreadCount: 0, isPhotoReportOpen: deal.rawStatus != "closed",
             isArchived: deal.archived,
             rawStatus: deal.rawStatus, reportStatus: deal.reportStatus)
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            HStack {
                                DealStatusBadges(deal: deal)
                                Spacer()
                                Text("#\(deal.id)")
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Text(deal.title)
                                .font(Typography.title)
                                .foregroundStyle(Theme.textPrimary)

                            if let address = deal.address {
                                infoRow("mappin.and.ellipse", address)
                            }
                            if let date = deal.eventDate {
                                infoRow("calendar", RelativeDate.short(date))
                            }
                            infoRow("folder", deal.storageFolder)
                        }
                    }

                    NavigationLink {
                        ChatView(chat: chatForDeal, currentUserId: session.currentUser?.id ?? "")
                            .environmentObject(session)
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                            Text("Перейти в чат заказа")
                        }
                        .font(Typography.button).foregroundStyle(Theme.textOnAccent)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())

                    Text("Команда на заказе")
                        .font(Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.leading, Spacing.xs)

                    VStack(spacing: Spacing.xs) {
                        if participants.isEmpty {
                            Text("Загрузка участников…")
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Spacing.s)
                        }
                        ForEach(participants) { user in
                            NavigationLink {
                                UserProfileView(user: user)
                            } label: {
                                memberRow(user)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, Spacing.m)
            }
        }
        .navigationTitle("Заказ")
        .navigationBarTitleDisplayMode(.inline)
        // Отсюда открывается чат, а он вкладки прячет: объявляем видимость и на
        // этом конце, иначе бар возвращается уже после перехода, поверх экрана.
        .toolbar(.visible, for: .tabBar)
        .toolbar {
            if session.currentUser?.isAdmin == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEdit = true } label: { Image(systemName: "square.and.pencil") }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditEventView(dealId: deal.id)
                .environmentObject(session)
        }
        .task { participants = await session.directory.members(dealId: deal.id) }
    }

    @ViewBuilder
    private func memberAvatar(_ user: User) -> some View {
        if let url = user.avatarURL {
            CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                Avatar(name: user.fullName, size: 42, id: user.id)
            }
            .frame(width: 42, height: 42).clipShape(Circle())
        } else {
            Avatar(name: user.fullName, size: 42, id: user.id)
        }
    }

    private func memberRow(_ user: User) -> some View {
        HStack(spacing: Spacing.s) {
            memberAvatar(user)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.fullName)
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(user.position.isEmpty ? Presence.text(isOnline: false, lastSeen: user.lastSeen) : user.position)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        .contentShape(Rectangle())
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(Typography.subheadline)
            .foregroundStyle(Theme.textSecondary)
    }
}
