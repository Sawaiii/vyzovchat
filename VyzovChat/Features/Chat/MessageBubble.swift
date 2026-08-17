import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isMine: Bool
    let sender: User?
    var replyToMe: Bool = false

    /// Статус доставки своего сообщения в ЛС.
    enum ReadState { case none, sent, delivered, read }

    /// Сколько участников прочитали моё сообщение в мероприятии.
    struct GroupReadInfo { let read: Int; let total: Int }

    var canDelete: Bool = false
    var canEdit: Bool = false
    var isDM: Bool = false
    var readState: ReadState = .none
    var readAt: Date? = nil
    var groupRead: GroupReadInfo? = nil
    var highlighted: Bool = false
    /// ФИО в нижнем регистре → id сотрудника: по ним в тексте находим
    /// упоминания и делаем их кликабельными.
    var mentionPeople: [String: String] = [:]
    var onLongPress: () -> Void = {}
    var onReply: () -> Void = {}
    var onReact: (String) -> Void = { _ in }
    var onOpenProfile: (String) -> Void = { _ in }
    var onOpenMedia: (Message.Attachment) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onEdit: () -> Void = {}
    var onForward: () -> Void = {}
    var onOpenReply: (String) -> Void = { _ in }
    /// Мне положено отмечаться «ознакомлен» (участник и старший).
    var canAck: Bool = false
    var onAck: () -> Void = {}
    var onShowAcks: () -> Void = {}

    private var displayName: String { message.senderName ?? sender?.shortName ?? "—" }

    var body: some View {
        if message.isNotice {
            noticeCard
        } else if message.isSystem {
            systemBubble
        } else {
            HStack(alignment: .bottom, spacing: Spacing.xs) {
                if isMine { Spacer(minLength: 40) }
                if !isMine {
                    Button { onOpenProfile(message.senderId) } label: { avatar }
                        .buttonStyle(.plain)
                }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                    bubble
                    if !message.reactions.isEmpty { reactionsRow }
                }
                if !isMine { Spacer(minLength: 40) }
            }
            .padding(.vertical, 2)
        }
    }

    private var avatar: some View {
        Group {
            if let url = message.senderAvatarURL ?? sender?.avatarURL {
                CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                    Avatar(name: displayName, size: 30, id: message.senderId)
                }
                .frame(width: 30, height: 30).clipShape(Circle())
            } else {
                Avatar(name: displayName, size: 30, id: message.senderId)
            }
        }
    }

    /// Есть ли что показать в цитате. Сообщение, на которое отвечали, могли
    /// удалить — тогда `reply_to` у сервера остаётся, а превью пропадает, и
    /// рисовать пустую сноску «Ответ» с пустой строкой незачем.
    private var hasReplyQuote: Bool {
        message.replyToId != nil && (message.replySender != nil || message.replyPreview != nil)
    }

    /// Сообщение только с фото/видео (без текста/цитаты/пересылки) — рисуем без цветного фона.
    private var isMediaOnly: Bool {
        (message.text?.isEmpty ?? true) && !message.attachments.isEmpty
            && !hasReplyQuote && message.forwardedFrom == nil
            && message.attachments.allSatisfy { $0.isImage || $0.isVideo }
    }

    private var bubble: some View {
        Group {
            if isMediaOnly { mediaOnlyBubble } else { textBubble }
        }
    }

    private var mediaOnlyBubble: some View {
        ZStack(alignment: .bottomTrailing) {
            if message.attachments.count > 1 {
                albumGrid
            } else {
                VStack(spacing: 3) {
                    ForEach(message.attachments) { att in attachmentView(att) }
                }
            }
            timeChip.padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.accent.opacity(highlighted ? 0.35 : 0))
                .animation(.easeInOut(duration: 0.4), value: highlighted)
        )
        .onLongPressGesture(minimumDuration: Self.longPress, maximumDistance: 10) {
            Haptics.tap()
            onLongPress()
        }
    }

    /// Насколько держать сообщение до появления меню — быстрее, чем по умолчанию,
    /// но это именно долгое нажатие: при скролле (движении пальца) не срабатывает
    /// и не открывает фото на отпускании — в отличие от simultaneousGesture.
    static let longPress: Double = 0.18

    /// Тап выполняет действие элемента (открыть медиа / профиль / перейти к ответу),
    /// а удержание (тот же тайминг, что и у сообщения) вызывает меню взаимодействия.
    /// ExclusiveGesture отдаёт приоритет удержанию, поэтому тап после него не
    /// срабатывает, а единый распознаватель на самом элементе убирает конкуренцию с
    /// внешним пузырём — меню появляется без задержки на любой части сообщения
    /// (в т.ч. на цитате ответа и на медиа).
    private func tapOrHoldGesture(onTap: @escaping () -> Void) -> some Gesture {
        ExclusiveGesture(
            LongPressGesture(minimumDuration: Self.longPress, maximumDistance: 10)
                .onEnded { _ in
                    Haptics.tap()
                    onLongPress()
                },
            TapGesture().onEnded { onTap() }
        )
    }

    /// Время + метка редактирования + галочки/счётчик прочтений (обнимает контент).
    private var metaRow: some View {
        HStack(spacing: 3) {
            if message.editedAt != nil {
                Text("изм.").font(.caption2).foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            if let groupRead {
                Label("\(groupRead.read)", systemImage: "eye.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            Text(RelativeDate.time(message.sentAt))
                .font(.caption2).foregroundStyle(Theme.textPrimary.opacity(0.55))
            ReadTicks(state: readState)
        }
    }

    /// Альбом: несколько фото мозаикой «как в Telegram» — без пустых ячеек, ряды с
    /// разным числом фото (см. AlbumMosaicLayout). Внешние скругления даёт обрезка
    /// mediaOnlyBubble, поэтому сами плитки без радиуса — мозаика бесшовная.
    private static let albumWidth: CGFloat = 240

    /// Пропорция вложения (ширина/высота) из размеров БД, или 0 если неизвестно.
    static func aspect(_ a: Message.Attachment) -> CGFloat {
        a.width > 0 && a.height > 0 ? CGFloat(a.width) / CGFloat(a.height) : 0
    }

    /// Сколько плиток показываем в мозаике. Альбом бывает и на полсотни снимков:
    /// без ограничения мозаика вырастала на несколько экранов — лента прокручивалась
    /// рывками, а меню по удержанию уезжало за край, потому что считалось от кадра
    /// сообщения. Остальные снимки прячем под «+N» и открываем в галерее.
    static let albumMaxTiles = 10

    private var albumGrid: some View {
        let shown = Array(message.attachments.prefix(Self.albumMaxTiles))
        let hidden = message.attachments.count - shown.count
        let aspects = shown.map(Self.aspect)
        let layout = AlbumMosaicLayout.frames(aspects: aspects, count: shown.count, width: Self.albumWidth)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, att in
                let r = idx < layout.rects.count ? layout.rects[idx] : .zero
                let isLast = idx == shown.count - 1 && hidden > 0
                Color.clear
                    .frame(width: r.width, height: r.height)
                    .overlay(
                        CachedAsyncImage(url: att.previewURL) { $0.resizable().scaledToFill() } placeholder: {
                            Theme.panel2
                        }
                    )
                    .overlay {
                        if isLast {
                            ZStack {
                                Color.black.opacity(0.45)
                                Text("+\(hidden)")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        } else if att.isVideo {
                            Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(tapOrHoldGesture { onOpenMedia(att) })
                    .offset(x: r.minX, y: r.minY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    private var timeChip: some View {
        HStack(spacing: 3) {
            if message.editedAt != nil { Text("изм.") }
            Text(RelativeDate.time(message.sentAt))
            ReadTicks(state: readState)
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.black.opacity(0.4), in: Capsule())
    }

    private var textBubble: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !isMine {
                // Не Button: кнопка съедала долгое нажатие, и зажатие на нике
                // не открывало меню сообщения. Тап открывает профиль как раньше.
                Text(displayName).font(.caption.weight(.semibold)).foregroundStyle(Theme.groupTitle)
                    .contentShape(Rectangle())
                    .gesture(tapOrHoldGesture { onOpenProfile(message.senderId) })
            }

            if let from = message.forwardedFrom {
                // Не Button — по той же причине, что ник и цитата: кнопка внутри
                // пузыря съедала долгое нажатие, и меню сообщения не открывалось.
                Label("Переслано от \(from)", systemImage: "arrowshape.turn.up.right.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.bubbleLink)
                    .contentShape(Rectangle())
                    // У старых пересылок id автора сервер не сохранял — тогда
                    // это просто подпись, открывать нечего.
                    .gesture(tapOrHoldGesture {
                        if let id = message.forwardedFromId { onOpenProfile(id) }
                    })
            }

            if hasReplyQuote { replyQuote }

            ForEach(message.attachments) { att in attachmentView(att) }

            if let text = message.text, !text.isEmpty {
                // Текст и время в одной строке снизу — пузырь обнимает контент, без пустот.
                HStack(alignment: .bottom, spacing: 6) {
                    Text(MentionText.build(text, people: mentionPeople, color: Theme.bubbleLink))
                        .font(Typography.body).foregroundStyle(Theme.textPrimary)
                        // Ссылка у упоминания своя, ненастоящая — перехватываем
                        // её здесь и открываем профиль.
                        .environment(\.openURL, OpenURLAction { url in
                            guard let id = MentionText.workerId(from: url) else { return .systemAction }
                            onOpenProfile(id)
                            return .handled
                        })
                    metaRow
                }
            } else {
                metaRow
            }
        }
        .padding(9)
        .background(isMine ? Theme.bubbleMine : Theme.bubbleOther)
        .clipShape(BubbleShape(isMine: isMine))
        .overlay(
            BubbleShape(isMine: isMine)
                .fill(Theme.accent.opacity(highlighted ? 0.35 : 0))
                .animation(.easeInOut(duration: 0.4), value: highlighted)
        )
        // Тёмный контур по краю. Свой пузырь — синий средней темноты, и на
        // светлых обоях (сирень, мята) его край растворяется: разница с фоном
        // около двух крат, этого мало. Контур даёт границу независимо от того,
        // светлее фон пузыря или темнее; белая обводка, как на прочих панелях
        // приложения, на светлых обоях не сработала бы.
        .overlay(
            BubbleShape(isMine: isMine)
                .stroke(Color.black.opacity(0.28), lineWidth: 0.5)
        )
        .onLongPressGesture(minimumDuration: Self.longPress, maximumDistance: 10) {
            Haptics.tap()
            onLongPress()
        }
    }


    /// Не Button по той же причине, что и ник: кнопка внутри пузыря съедала
    /// долгое нажатие и меню не открывалось.
    private var replyQuote: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(replyToMe ? "Ответ вам · \(message.replySender ?? "")" : (message.replySender ?? "Ответ"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(replyToMe ? Theme.groupTitle : Theme.accent)
            Text(message.replyPreview ?? "")
                .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .frame(maxWidth: 240, alignment: .leading)
        // Полоску держим в фоне (высота = высоте текста), а не гибким Rectangle в
        // HStack: тот «съедал» лишнюю высоту VStack-а пузыря рядом с высоким фото и
        // цитата растягивалась. fixedSize — использовать идеальную высоту, а не
        // навязанную.
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.2))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(replyToMe ? Theme.groupTitle : Theme.accent)
                    .frame(width: 3)
                    .padding(.vertical, 3)
            }
        )
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .gesture(tapOrHoldGesture { if let rid = message.replyToId { onOpenReply(rid) } })
    }

    private var reactionsRow: some View {
        HStack(spacing: 4) {
            ForEach(message.reactionCounts) { item in
                Button { onReact(item.emoji) } label: {
                    Text("\(item.emoji) \(item.count)")
                        .font(.caption2)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.panel2, in: Capsule())
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Вложения

    @ViewBuilder
    private func attachmentView(_ att: Message.Attachment) -> some View {
        if att.isImage {
            imageTile(att)
        } else if att.isVideo {
            videoTile(att)
        } else if att.isAudio {
            VoiceBubble(attachment: att, isMine: isMine)
        } else {
            fileRow(att)
        }
    }

    @ViewBuilder
    private func imageTile(_ att: Message.Attachment) -> some View {
        let a = Self.aspect(att)
        Group {
            if a > 0 {
                // Размеры известны из БД — сразу резервируем правильную высоту
                // (лента не «прыгает» при догрузке), фото заполняет кадр.
                let w: CGFloat = 240
                let h = min(max(w / a, 90), 360)
                Color.clear
                    .frame(width: w, height: h)
                    .overlay(
                        CachedAsyncImage(url: att.previewURL) { $0.resizable().scaledToFill() }
                            placeholder: { Theme.panel2 }
                    )
                    .clipped()
            } else {
                // Размеров нет — как раньше: высота по факту загрузки.
                CachedAsyncImage(url: att.previewURL) { $0.resizable().scaledToFit() } placeholder: {
                    placeholderTile(icon: nil).frame(width: 200, height: 150)
                }
                .frame(maxWidth: 240)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isMediaOnly ? 14 : 10, style: .continuous))
        .contentShape(Rectangle())
        .gesture(tapOrHoldGesture { onOpenMedia(att) })
    }

    private func videoTile(_ att: Message.Attachment) -> some View {
        RoundedRectangle(cornerRadius: isMediaOnly ? 14 : 10, style: .continuous)
            .fill(Color.black.opacity(0.85))
            .frame(width: 240, height: 150)
            .overlay(Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.95)))
            .overlay(alignment: .bottomLeading) {
                Text(att.fileName ?? "Видео").font(.caption2).foregroundStyle(.white.opacity(0.9)).padding(6).lineLimit(1)
            }
            .contentShape(Rectangle())
            .gesture(tapOrHoldGesture { onOpenMedia(att) })
    }

    private func fileRow(_ att: Message.Attachment) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "doc.fill").font(.title3).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(att.fileName ?? "Файл").font(Typography.callout.weight(.medium)).foregroundStyle(.white).lineLimit(1)
                if let size = att.sizeBytes {
                    Text(byteText(size)).font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: 210, alignment: .leading)
    }

    private func placeholderTile(icon: String?) -> some View {
        ZStack {
            Rectangle().fill(Theme.panel2)
            if let icon { Image(systemName: icon).font(.title2).foregroundStyle(Theme.textSecondary) }
            else { ProgressView().tint(.white) }
        }
    }

    /// Чем строка выделяется. Приезд на площадку — единственное зелёное: его
    /// ждут и высматривают в ленте, остальные события мероприятия спокойнее.
    private var systemStyle: (color: Color, icon: String) {
        switch message.systemKind {
        case "shift_in":     return (Theme.success, "clock.badge.checkmark")
        case "shift_out":    return (Theme.textSecondary, "checkmark.seal")
        case "stage_done":   return (Theme.accent, "checkmark.circle.fill")
        case "stage_undone": return (Theme.textSecondary, "arrow.uturn.backward")
        // Состав: кого добавили, кто пришёл по ссылке, кому сменили роль.
        case "member_add", "member_join": return (Theme.textSecondary, "person.badge.plus")
        case "member_out":                return (Theme.textSecondary, "person.badge.minus")
        case "member_role":               return (Theme.textSecondary, "person.crop.circle.badge.checkmark")
        default:             return (Theme.textSecondary, "info.circle")
        }
    }

    /// Врезка «вводные из сделки» и «важное».
    ///
    /// Не пузырь: это уведомление, а не реплика. У вводных автора нет вовсе
    /// (в базе им числится создатель чата), у важного он виден — по объявлению
    /// задают вопросы. Внизу — отметка «Ознакомлен» и счётчик отметившихся.
    private var noticeCard: some View {
        let tint = noticeStyle.color
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: noticeStyle.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(noticeStyle.title)
                    .font(.system(size: 11, weight: .semibold))
                // У важного и жалобы автор виден: по ним задают вопросы. У вводных
                // из сделки и отзыва клиента автора нет — это не чья-то реплика.
                if message.isAlarm || message.isComplaint,
                   let author = message.senderName, !author.isEmpty {
                    Text("· " + author).font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)

            Text(message.text ?? "")
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if message.needsAck {
                HStack(spacing: Spacing.s) {
                    if canAck && !message.ackMe {
                        Button("Ознакомлен") { onAck() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textOnAccent)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(tint, in: Capsule())
                    } else if message.ackMe {
                        Label("вы ознакомились", systemImage: "checkmark.circle.fill")
                            .font(.caption2).foregroundStyle(Theme.success)
                    }
                    Spacer(minLength: 0)
                    Button { onShowAcks() } label: {
                        Text(ackCountText)
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chatOverlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous), tint: tint)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.vertical, Spacing.xs)
    }

    /// Чем врезка подписана и какого она цвета. Жалоба и важное — янтарём, чтобы
    /// не спутались с вводными из сделки; отзыв клиента — зелёным.
    private var noticeStyle: (title: String, icon: String, color: Color) {
        switch message.systemKind {
        case "alarm":     return ("Важное", "exclamationmark.triangle.fill", Theme.warning)
        case "complaint": return ("Жалоба", "exclamationmark.bubble.fill", Theme.danger)
        case "review":    return ("Отзыв клиента", "star.fill", Theme.success)
        default:          return ("Вводные из сделки", "doc.text.fill", Theme.accent)
        }
    }

    /// «ознакомились 1 из 4» — одинокая цифра ни о чём не говорит.
    private var ackCountText: String {
        message.ackTotal > 0
            ? "ознакомились \(message.ackCount) из \(message.ackTotal)"
            : "ознакомились \(message.ackCount)"
    }

    private var systemBubble: some View {
        let style = systemStyle
        return HStack(spacing: 6) {
            Image(systemName: style.icon).font(.system(size: 11, weight: .semibold))
            Text(message.text ?? "")
                .font(Typography.caption)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, Spacing.s).padding(.vertical, 6)
        .chatOverlay(Capsule(), tint: style.color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
    }

    private func byteText(_ bytes: Int) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}

/// Галочки статуса: одна серая (отправлено), две серые (доставлено), две синие (прочитано).
struct ReadTicks: View {
    let state: MessageBubble.ReadState

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        case .delivered:
            doubleCheck(Theme.textPrimary.opacity(0.55))
        case .read:
            doubleCheck(Theme.accent)
        }
    }

    private func doubleCheck(_ color: Color) -> some View {
        HStack(spacing: -3) {
            Image(systemName: "checkmark")
            Image(systemName: "checkmark")
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(color)
    }
}

/// Форма пузыря с «хвостиком» на нужной стороне.
struct BubbleShape: Shape, InsettableShape {
    var isMine: Bool
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self; copy.inset += amount; return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius: CGFloat = 14
        let corners: UIRectCorner = isMine
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]
        return Path(UIBezierPath(roundedRect: r, byRoundingCorners: corners,
                                 cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
