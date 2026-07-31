import SwiftUI

/// Смены мероприятия: своя отметка «я на месте» и сводка по бригаде.
///
/// Сервер сам решает, чьи смены показать: обычный сотрудник видит только свою,
/// куратор — ещё и тех, кого позвал по ссылке, админ чата — все. Поэтому список
/// показываем как есть, без фильтрации на клиенте.
struct EventShiftsView: View {
    let dealId: String
    let eventTitle: String
    /// Админ чата может открывать и закрывать смены за сотрудников.
    let isChatAdmin: Bool

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var shifts: [CheckinDTO] = []
    @State private var members: [User] = []
    @State private var isLoading = true
    @State private var busy = false
    @State private var busyWorkerId: String?
    @State private var errorText: String?

    private var myId: String { session.currentUser?.id ?? "" }

    /// Моя открытая смена (без времени завершения).
    private var myOpenShift: CheckinDTO? {
        shifts.first { String($0.worker_id) == myId && $0.finished_at == nil }
    }

    private var myClosedToday: Bool {
        shifts.contains { String($0.worker_id) == myId && $0.finished_at != nil }
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
                            myShiftCard
                            if let errorText { ErrorBanner(text: errorText) }
                            shiftsList
                            if isChatAdmin { manualCard }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle("Смены")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            // Отметку мог поставить кто-то другой (или админ за нас) — обновляем на лету.
            .onReceive(RealtimeService.shared.checkins) { info in
                guard info.eventId == dealId else { return }
                apply(info.checkin)
            }
        }
    }

    // MARK: - Своя смена

    private var myShiftCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(eventTitle)
                    .font(Typography.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)

                if let open = myOpenShift {
                    Label("На смене с \(time(open.checked_at))", systemImage: "clock.badge.checkmark")
                        .font(Typography.callout).foregroundStyle(Theme.success)
                    PrimaryButton(title: "Завершить смену", isLoading: busy, isEnabled: !busy) {
                        Task { await mark(checkIn: false) }
                    }
                } else if myClosedToday {
                    Label("Смена завершена", systemImage: "checkmark.seal")
                        .font(Typography.callout).foregroundStyle(Theme.textSecondary)
                    SecondaryButton(title: "Открыть смену снова", icon: "play.circle") {
                        Task { await mark(checkIn: true) }
                    }
                    .disabled(busy)
                } else {
                    PrimaryButton(title: "Я на месте", isLoading: busy, isEnabled: !busy) {
                        Task { await mark(checkIn: true) }
                    }
                }

                Text("Отметка сохраняет координаты — так подтверждается, что вы на площадке. Без доступа к геоданным отметиться нельзя; попросите админа чата отметить вас вручную.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Список смен

    private var shiftsList: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Отметки").font(Typography.headline).foregroundStyle(Theme.textPrimary)
            if shifts.isEmpty {
                Text("Пока никто не отмечался.")
                    .font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(shifts, id: \.worker_id) { shift in
                shiftRow(shift)
            }
        }
    }

    private func shiftRow(_ shift: CheckinDTO) -> some View {
        HStack(spacing: Spacing.s) {
            Avatar(name: shift.fio, size: 36, id: String(shift.worker_id))
            VStack(alignment: .leading, spacing: 2) {
                Text(shift.fio).font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(interval(shift)).font(.caption2).foregroundStyle(Theme.textSecondary)
                // Кто отметил, если это делал не сам сотрудник.
                if let note = markedBy(shift) {
                    Text(note).font(.caption2).foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            Circle()
                .fill(shift.finished_at == nil ? Theme.success : Theme.textSecondary)
                .frame(width: 8, height: 8)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    // MARK: - Отметка за сотрудника

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Отметить за сотрудника").font(Typography.headline).foregroundStyle(Theme.textPrimary)
            Text("Если у человека сел телефон или нет доступа к геоданным. В отметке останется, что её проставили вы.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)

            ForEach(candidates) { member in
                let open = shifts.first { $0.worker_id == Int(member.id) && $0.finished_at == nil }
                HStack(spacing: Spacing.s) {
                    Avatar(name: member.fullName, size: 32, id: member.id)
                    Text(member.fullName).font(Typography.callout)
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    if busyWorkerId == member.id {
                        ProgressView().tint(Theme.accent)
                    } else {
                        Button(open == nil ? "Открыть" : "Закрыть") {
                            Task { await markFor(member, checkIn: open == nil) }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
                .padding(Spacing.s)
                .glass(cornerRadius: Theme.cornerSmall, elevated: false)
            }
        }
    }

    /// Кому можно ставить отметку: складу смены не отмечают (сервер это запрещает).
    private var candidates: [User] {
        members.filter { $0.eventRole != "warehouse" }
    }

    // MARK: - Действия

    private func mark(checkIn: Bool) async {
        busy = true
        errorText = nil
        defer { busy = false }

        // Координаты обязательны: сервер без них отметку не примет, и это
        // осознанное правило — смена подтверждает присутствие на площадке.
        LocationProvider.shared.requestAuthorization()
        guard let geo = await LocationProvider.shared.current() else {
            errorText = ShiftError.geoUnavailable.localizedDescription
            Haptics.warning()
            return
        }
        do {
            let result = checkIn
                ? try await session.shifts.checkIn(dealId: dealId, lat: geo.lat, lng: geo.lng)
                : try await session.shifts.checkOut(dealId: dealId, lat: geo.lat, lng: geo.lng)
            apply(result)
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func markFor(_ member: User, checkIn: Bool) async {
        busyWorkerId = member.id
        errorText = nil
        defer { busyWorkerId = nil }
        do {
            let result = checkIn
                ? try await session.shifts.checkInFor(dealId: dealId, workerId: member.id)
                : try await session.shifts.checkOutFor(dealId: dealId, workerId: member.id)
            apply(result)
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    /// Вставить или заменить отметку сотрудника — и от своего действия, и из сокета.
    private func apply(_ shift: CheckinDTO) {
        if let idx = shifts.firstIndex(where: { $0.worker_id == shift.worker_id }) {
            shifts[idx] = shift
        } else {
            shifts.append(shift)
        }
    }

    private func load() async {
        async let loadedShifts = session.shifts.shifts(dealId: dealId)
        async let loadedMembers = isChatAdmin ? session.directory.members(dealId: dealId) : []
        let (s, m) = await (loadedShifts, loadedMembers)
        shifts = s
        members = m
        isLoading = false
    }

    // MARK: - Форматирование

    private func time(_ iso: String) -> String {
        guard let date = DateParse.iso(iso) else { return "—" }
        return Self.timeFormatter.string(from: date)
    }

    private func interval(_ shift: CheckinDTO) -> String {
        let start = time(shift.checked_at)
        guard let finished = shift.finished_at else { return "с \(start) — на смене" }
        return "\(start) — \(time(finished))"
    }

    private func markedBy(_ shift: CheckinDTO) -> String? {
        let opened = shift.opened_by?.isEmpty == false ? shift.opened_by : nil
        let closed = shift.closed_by?.isEmpty == false ? shift.closed_by : nil
        switch (opened, closed) {
        case let (o?, c?) where o == c: return "отметил(а) \(o)"
        case let (o?, c?):              return "открыл(а) \(o), закрыл(а) \(c)"
        case let (o?, nil):             return "открыл(а) \(o)"
        case let (nil, c?):             return "закрыл(а) \(c)"
        default:                        return nil
        }
    }

    // Формат один на весь экран: создавать его в цикле по строкам — заметно дорого.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()
}
