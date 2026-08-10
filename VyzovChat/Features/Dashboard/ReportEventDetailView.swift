import SwiftUI

/// Мероприятие целиком, как оно видно из отчёта: фото, смены, документы,
/// претензии — и переход в чат.
///
/// Всё собрано из той же карточки, что уже пришла в дашборде: отдельного
/// запроса за подробностями сервер не предлагает, а данных в ней хватает.
struct ReportEventDetailView: View {
    let event: DashEventDTO
    let company: String?
    /// Сколько человек в составе — знаменатель «на смене».
    let membersTotal: Int?

    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.openURL) private var openURL
    @State private var mediaPreview: MediaPreview?

    private var checkins: [CheckinDTO] { event.checkins ?? [] }
    private var onShift: Int { checkins.filter { $0.finished_at == nil }.count }
    private var photos: [ReportPhotoDTO] { event.report_photos ?? [] }
    private var docs: [DocumentDTO] { event.docs ?? [] }
    private var claims: [ClaimDTO] { event.claims ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                ShiftDetail.chatButton(eventId: event.id)
                if !photos.isEmpty { photoSection }
                shiftsSection
                if !docs.isEmpty { docsSection }
                if !claims.isEmpty { claimsSection }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, Spacing.s)
        }
        .background(AmbientBackground().ignoresSafeArea())
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $mediaPreview) { preview in
            MediaPager(items: preview.items, startIndex: preview.index)
        }
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let company, !company.isEmpty {
                CompanyBadge(name: company, compact: false)
            }

            if let admins = event.admins, !admins.isEmpty {
                FlowLayout(spacing: 4) {
                    Text("Главный:").font(.caption2).foregroundStyle(Theme.textSecondary)
                    ForEach(admins) { admin in LeaderChip(fio: admin.fio) }
                }
            }

            if event.photos_restricted == true {
                Label("ФОТО НЕЛЬЗЯ БРАТЬ", systemImage: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.danger, in: Capsule())
            }

            HStack(spacing: Spacing.xs) {
                ShiftDetail.tile("\(photos.count)", "фото в отчёте", Theme.textPrimary)
                ShiftDetail.tile("\(onShift)/\(membersTotal ?? checkins.count)", "на смене",
                                 onShift > 0 ? Theme.success : Theme.textPrimary)
                ShiftDetail.tile("\(docs.count)", "документов", Theme.textPrimary)
                ShiftDetail.tile("\(claims.filter(\.isOpen).count)", "претензий",
                                 claims.contains(where: \.isOpen) ? Theme.warning : Theme.textPrimary)
            }
        }
    }

    // MARK: - Фото отчёта

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle("ФОТО ОТЧЁТА")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(Array(photos.enumerated()), id: \.offset) { idx, photo in
                    Button { open(at: idx) } label: {
                        CachedAsyncImage(url: AppConfig.mediaURL(photo.thumb ?? photo.full)) {
                            $0.resizable().scaledToFill()
                        } placeholder: {
                            Theme.panel2
                        }
                        .frame(height: 92)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func open(at index: Int) {
        let items = photos.enumerated().map { idx, photo in
            Message.Attachment(id: "report-\(idx)",
                               remoteURL: AppConfig.mediaURL(photo.full ?? photo.thumb),
                               isVideo: false, isFile: false)
        }
        mediaPreview = MediaPreview(items: items, index: index)
    }

    // MARK: - Смены

    private var shiftsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle("КТО БЫЛ НА МЕРОПРИЯТИИ")
            if checkins.isEmpty {
                Text("Отметок о смене нет.").font(.caption2).foregroundStyle(Theme.textSecondary)
            } else {
                // Кто ещё на смене — сверху: по ним и вопросы.
                // Ключ по позиции: один человек мог открывать смену не раз, а
                // отдельного id у отметки сервер не даёт.
                ForEach(Array(sortedCheckins.enumerated()), id: \.offset) { _, checkin in
                    checkinRow(checkin)
                }
            }
        }
    }

    private var sortedCheckins: [CheckinDTO] {
        checkins.sorted {
            ($0.finished_at == nil) == ($1.finished_at == nil)
                ? $0.fio < $1.fio
                : ($0.finished_at == nil)
        }
    }

    private func checkinRow(_ checkin: CheckinDTO) -> some View {
        HStack(spacing: Spacing.xs) {
            Avatar(name: checkin.fio, size: 28, id: String(checkin.worker_id))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(checkin.fio.isEmpty ? "Без имени" : checkin.fio)
                        .font(Typography.callout).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    ShiftDetail.roleChip(checkin.role)
                }
                Text(interval(checkin))
                    .font(.caption2)
                    .foregroundStyle(checkin.finished_at == nil ? Theme.success : Theme.textSecondary)
                if let marked = markedBy(checkin) {
                    Text(marked).font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Spacing.xs)
            Text(ShiftsSummary.hours(duration(checkin)))
                .font(Typography.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    /// Незакрытая смена идёт до «сейчас» — иначе часы занижались бы ровно на
    /// тех, кто прямо сейчас работает.
    private func duration(_ checkin: CheckinDTO) -> TimeInterval {
        guard let start = DateParse.iso(checkin.checked_at) else { return 0 }
        let end = checkin.finished_at.flatMap(DateParse.iso) ?? Date()
        return max(0, end.timeIntervalSince(start))
    }

    private func interval(_ checkin: CheckinDTO) -> String {
        let from = DateParse.iso(checkin.checked_at).map { ShiftDetail.time.string(from: $0) } ?? "—"
        guard let finished = checkin.finished_at.flatMap(DateParse.iso) else { return "\(from) → на смене" }
        return "\(from) → \(ShiftDetail.time.string(from: finished))"
    }

    private func markedBy(_ checkin: CheckinDTO) -> String? {
        var parts: [String] = []
        if let opened = checkin.opened_by, !opened.isEmpty { parts.append("открыл: \(opened)") }
        if let closed = checkin.closed_by, !closed.isEmpty { parts.append("закрыл: \(closed)") }
        // …и правка времени задним числом: в отчёте она должна быть видна.
        if let edit = checkin.editNote { parts.append(edit) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Документы и претензии

    private var docsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle("ДОКУМЕНТЫ")
            ForEach(docs) { doc in
                Button {
                    // Ссылки подписанные и живут ограниченное время — открываем
                    // ту, что пришла с документом, а не собираем свою.
                    if let raw = doc.file_url ?? doc.download_url, let url = URL(string: raw) {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.text").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(doc.title ?? doc.typeTitle).font(Typography.callout)
                                .foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text(doc.typeTitle).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: Spacing.xs)
                        if doc.file_url != nil || doc.download_url != nil {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(Spacing.s)
                    .glass(cornerRadius: Theme.cornerSmall, elevated: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle("ПРЕТЕНЗИИ")
            ForEach(claims) { claim in
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(claim.isOpen ? Theme.warning : Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(claim.statusTitle).font(Typography.callout)
                            .foregroundStyle(Theme.textPrimary)
                        if let author = claim.author_fio, !author.isEmpty {
                            Text(author).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: Spacing.xs)
                    Text("\((claim.items ?? []).count) поз.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                .padding(Spacing.s)
                .glass(cornerRadius: Theme.cornerSmall, elevated: false)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Spacing.s)
    }
}

/// Старший мероприятия. Жёлтым, а не акцентом: акцентом на карточке отчёта
/// покрашено всё подряд — «новое», «в чат», — и старший в нём терялся.
struct LeaderChip: View {
    let fio: String

    var body: some View {
        Label(fio, systemImage: "star.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.groupTitle)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.groupTitle.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(Theme.groupTitle.opacity(0.5), lineWidth: 1))
    }
}
