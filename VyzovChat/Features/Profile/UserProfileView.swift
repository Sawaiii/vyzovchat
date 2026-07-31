import SwiftUI

/// Профиль другого сотрудника: аватар, ФИО, должность, статус «в сети / был в сети», контакты.
struct UserProfileView: View {
    let user: User
    var sharedAttachments: [Message.Attachment] = []
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var realtime = RealtimeService.shared
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.openURL) private var openURL
    @State private var mediaPreview: MediaPreview?

    private var sharedMedia: [Message.Attachment] { sharedAttachments.filter { $0.isImage || $0.isVideo } }
    private var sharedFiles: [Message.Attachment] { sharedAttachments.filter { $0.isFile } }

    private var isOnline: Bool { realtime.isOnline(user.id) }
    private var lastSeen: Date? { realtime.lastSeen(for: user.id) ?? user.lastSeen }
    private var isSelf: Bool { session.currentUser?.id == user.id }

    private var dmChat: Chat {
        Chat(id: "dm-\(user.id)", dealId: "", title: user.fullName,
             participantIds: [user.id], lastMessagePreview: nil, lastMessageDate: nil,
             unreadCount: 0, isPhotoReportOpen: false,
             isDirect: true, otherUserId: user.id, avatarURL: user.avatarURL)
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(spacing: Spacing.m) {
                    header
                    if !isSelf { messageButton }
                    infoCard
                    if !sharedMedia.isEmpty { sharedMediaSection }
                    if !sharedFiles.isEmpty { sharedFilesSection }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, Spacing.m)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $mediaPreview) { preview in
            MediaPager(items: preview.items, startIndex: preview.index)
        }
    }

    // MARK: - Общие вложения

    private var sharedMediaSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Фото и видео").font(Typography.headline).foregroundStyle(Theme.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(sharedMedia) { att in
                    Button { openMedia(att) } label: {
                        ZStack {
                            CachedAsyncImage(url: att.remoteURL) { $0.resizable().scaledToFill() } placeholder: {
                                Rectangle().fill(Theme.panel2)
                            }
                            if att.isVideo {
                                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .frame(height: 104).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sharedFilesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Файлы").font(Typography.headline).foregroundStyle(Theme.textPrimary)
            VStack(spacing: Spacing.xs) {
                ForEach(sharedFiles) { att in
                    Button { if let url = att.remoteURL { openURL(url) } } label: {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "doc.fill").foregroundStyle(Theme.accent)
                            Text(att.fileName ?? "Файл").font(Typography.callout)
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
    }

    private func openMedia(_ att: Message.Attachment) {
        let idx = sharedMedia.firstIndex(where: { $0.id == att.id }) ?? 0
        mediaPreview = MediaPreview(items: sharedMedia, index: idx)
    }

    private func openAvatar() {
        guard let url = user.avatarURL else { return }
        let att = Message.Attachment(id: "avatar-\(user.id)", remoteURL: url)
        mediaPreview = MediaPreview(items: [att], index: 0)
    }

    private var messageButton: some View {
        NavigationLink {
            ChatView(chat: dmChat, currentUserId: session.currentUser?.id ?? "")
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "paperplane.fill")
                Text("Написать в личные")
            }
            .font(Typography.button).foregroundStyle(Theme.textOnAccent)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private var header: some View {
        VStack(spacing: Spacing.s) {
            ZStack(alignment: .bottomTrailing) {
                avatar
                    .onTapGesture { openAvatar() }
                OnlineDot(isOnline: isOnline, size: 20)
                    .offset(x: -6, y: -6)
            }
            Text(user.fullName)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if !user.position.isEmpty {
                Text(user.position)
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Label(Presence.text(isOnline: isOnline, lastSeen: lastSeen),
                  systemImage: isOnline ? "circle.fill" : "clock")
                .font(Typography.caption)
                .foregroundStyle(Presence.color(isOnline: isOnline))
        }
        .padding(.top, Spacing.s)
    }

    private var avatar: some View {
        Group {
            if let url = user.avatarURL {
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Avatar(name: user.fullName, size: 96, id: user.id)
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            } else {
                Avatar(name: user.fullName, size: 96, id: user.id)
            }
        }
    }

    private var infoCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                if !user.phone.isEmpty {
                    row("Телефон", user.phone, "phone.fill")
                    Divider().opacity(0.3)
                }
                if !user.login.isEmpty {
                    row("Логин", user.login, "person.fill")
                    Divider().opacity(0.3)
                }
                row("ID", user.id, "number")
            }
        }
    }

    private func row(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
            Text(title).font(Typography.callout).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Typography.callout.weight(.medium))
                .foregroundStyle(Theme.textPrimary).textSelection(.enabled)
        }
        .padding(.vertical, Spacing.s)
    }
}
