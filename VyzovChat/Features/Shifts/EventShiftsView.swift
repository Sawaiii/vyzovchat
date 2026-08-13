import SwiftUI
import UIKit

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
    /// Могу ли отметить свою смену. Наблюдатель и кладовщик не на площадке —
    /// им сервер откажет, и предлагать кнопку незачем.
    var canCheckin: Bool = true
    /// Правки задним числом (`me_rights.shift_cancel`): снять завершение, задать
    /// время, убрать смену целиком. Это право руководства, а не админа чата —
    /// админом чата бывает и обычный работник.
    var canEditShifts: Bool = false

    /// Что подтверждаем. Отметка пишет время и место и завершение отменить
    /// нельзя, поэтому спрашиваем перед обоими действиями.
    enum Confirm: String, Identifiable {
        case start, finish
        var id: String { rawValue }

        var title: String { self == .start ? "Отметиться на месте?" : "Завершить смену?" }
        var action: String { self == .start ? "Сделать снимок" : "Завершить" }
        var message: String {
            self == .start
                ? "Сначала снимок с площадки, потом координаты — так подтверждается, что вы действительно здесь."
                : "Отметим время окончания. Открыть эту смену заново может только руководство."
        }
    }

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.openURL) private var openURL

    @State private var shifts: [CheckinDTO] = []
    @State private var members: [User] = []
    @State private var isLoading = true
    @State private var busy = false
    @State private var busyWorkerId: String?
    @State private var errorText: String?
    @State private var confirming: Confirm?
    /// Камера для селфи с площадки — без снимка смену не открыть.
    @State private var showCamera = false
    /// Селфи, открытое крупно.
    @State private var photoPreview: ShiftPhoto?
    /// Смена, у которой правим время.
    @State private var editingShift: CheckinDTO?
    /// …и которую убираем целиком.
    @State private var cancellingShift: CheckinDTO?

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
                            if canCheckin { myShiftCard }
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
            // Смену отменили целиком — строка должна исчезнуть и у тех, кто
            // смотрит этот экран прямо сейчас.
            .onReceive(RealtimeService.shared.checkinRemoved) { info in
                guard info.eventId == dealId else { return }
                shifts.removeAll { String($0.worker_id) == info.workerId }
            }
            .sheet(item: $editingShift) { shift in
                ShiftTimesEditor(shift: shift) { started, finished in
                    await setTimes(shift, started: started, finished: finished)
                }
            }
            .confirmationDialog("Убрать смену целиком?",
                                isPresented: .init(get: { cancellingShift != nil },
                                                   set: { if !$0 { cancellingShift = nil } }),
                                titleVisibility: .visible) {
                Button("Убрать", role: .destructive) {
                    if let shift = cancellingShift { Task { await cancel(shift) } }
                    cancellingShift = nil
                }
                Button("Отмена", role: .cancel) { cancellingShift = nil }
            } message: {
                Text("Отметка \(cancellingShift?.fio ?? "") пропадёт из отчёта: в нём не должно оставаться выезда, которого не было.")
            }
            .alert(item: $confirming) { confirm in
                Alert(title: Text(confirm.title),
                      message: Text(confirm.message),
                      primaryButton: .default(Text(confirm.action)) {
                          // Начало смены идёт через камеру: сначала снимок, потом
                          // гео и запрос. Завершение — сразу, снимок там не нужен.
                          if confirm == .start { showCamera = true }
                          else { Task { await mark(checkIn: false) } }
                      },
                      secondaryButton: .cancel(Text("Отмена")))
            }
            .fullScreenCover(item: $photoPreview) { photo in
                ShiftPhotoView(photo: photo)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CheckinCamera(
                    onCapture: { image in
                        showCamera = false
                        Task { await startShift(selfie: image) }
                    },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
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
                        confirming = .finish
                    }
                } else if myClosedToday {
                    Label("Смена завершена", systemImage: "checkmark.seal")
                        .font(Typography.callout).foregroundStyle(Theme.textSecondary)
                    // Сам себе смену не переоткрывает никто: повторная отметка
                    // не снимает завершение, а начало переписала бы на текущее
                    // время. Снять завершение может только руководство —
                    // удержанием строки в списке ниже.
                    Text(canEditShifts
                            ? "Смена закрыта. Снять завершение можно удержанием строки в списке ниже."
                            : "Смена закрыта, отработанное время засчитано. Открыть её заново может только руководство.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                } else {
                    PrimaryButton(title: "Я на месте", isLoading: busy, isEnabled: !busy) {
                        confirming = .start
                    }
                }

                Text("Отметка сохраняет снимок с площадки и координаты. Без снимка и геоданных отметиться нельзя; попросите админа чата отметить вас вручную.")
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
            // Селфи с отметки вместо аватара: по нему и видно, что человек был
            // на площадке. По тапу открывается крупно.
            if let url = AppConfig.mediaURL(shift.photo_url) {
                Button { photoPreview = ShiftPhoto(url: url, fio: shift.fio) } label: {
                    CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                        Avatar(name: shift.fio, size: 36, id: String(shift.worker_id))
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Avatar(name: shift.fio, size: 36, id: String(shift.worker_id))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(shift.fio).font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(interval(shift)).font(.caption2).foregroundStyle(Theme.textSecondary)
                // Где открыли и где закрыли смену: раньше координаты завершения
                // сервер писал, но никто не показывал.
                geoRow(shift)
                // Тревога: смену закрыли далеко от места начала — обычно это
                // «завершил по дороге домой», и в сводке это надо видеть.
                if let far = shift.finishFarNote {
                    Label(far, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Кто отметил, если это делал не сам сотрудник.
                if let note = markedBy(shift) {
                    Text(note).font(.caption2).foregroundStyle(Theme.warning)
                }
                // …и кто правил время руками: иначе в отчёте появляются часы,
                // которых никто не проставлял.
                if let edit = shift.editNote {
                    Text(edit).font(.caption2).foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            Circle()
                .fill(shift.finished_at == nil ? Theme.success : Theme.textSecondary)
                .frame(width: 8, height: 8)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        .contentShape(Rectangle())
        .contextMenu {
            if canEditShifts {
                Button { editingShift = shift } label: {
                    Label("Задать время", systemImage: "clock.arrow.circlepath")
                }
                if shift.finished_at != nil {
                    Button { Task { await reopen(shift) } } label: {
                        Label("Снять завершение", systemImage: "arrow.uturn.backward")
                    }
                }
                Button(role: .destructive) { cancellingShift = shift } label: {
                    Label("Убрать смену", systemImage: "trash")
                }
            }
        }
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

    /// Открыть смену: снимок → хранилище → координаты → отметка.
    ///
    /// Порядок именно такой: снимок уже сделан, и если сначала спрашивать гео,
    /// человек с отключённой геолокацией снимал бы зря.
    private func startShift(selfie: UIImage) async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let photoKey = try await MediaUploader.uploadCheckinPhoto(selfie)
            // Координаты обязательны: сервер без них отметку не примет, и это
            // осознанное правило — смена подтверждает присутствие на площадке.
            LocationProvider.shared.requestAuthorization()
            guard let geo = await LocationProvider.shared.current() else {
                errorText = ShiftError.geoUnavailable.localizedDescription
                Haptics.warning()
                return
            }
            apply(try await session.shifts.checkIn(dealId: dealId, lat: geo.lat, lng: geo.lng,
                                                   photoKey: photoKey))
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    /// Завершение смены: снимок не нужен, только координаты.
    private func mark(checkIn: Bool) async {
        busy = true
        errorText = nil
        defer { busy = false }

        LocationProvider.shared.requestAuthorization()
        guard let geo = await LocationProvider.shared.current() else {
            errorText = ShiftError.geoUnavailable.localizedDescription
            Haptics.warning()
            return
        }
        do {
            apply(try await session.shifts.checkOut(dealId: dealId, lat: geo.lat, lng: geo.lng))
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

    // MARK: - Правки задним числом (руководство)

    private func reopen(_ shift: CheckinDTO) async {
        busyWorkerId = String(shift.worker_id)
        errorText = nil
        defer { busyWorkerId = nil }
        do {
            apply(try await session.shifts.reopenShift(dealId: dealId,
                                                       workerId: String(shift.worker_id)))
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func cancel(_ shift: CheckinDTO) async {
        busyWorkerId = String(shift.worker_id)
        errorText = nil
        defer { busyWorkerId = nil }
        do {
            try await session.shifts.cancelShift(dealId: dealId, workerId: String(shift.worker_id))
            shifts.removeAll { $0.worker_id == shift.worker_id }
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func setTimes(_ shift: CheckinDTO, started: Date?, finished: Date?) async {
        errorText = nil
        do {
            apply(try await session.shifts.setShiftTimes(dealId: dealId,
                                                         workerId: String(shift.worker_id),
                                                         checkedAt: started, finishedAt: finished))
            Haptics.success()
        } catch {
            errorText = shiftEditError(error)
            Haptics.warning()
        }
    }

    /// Ошибки правки смены словами.
    private func shiftEditError(_ error: Error) -> String {
        guard case let APIError.http(_, serverMessage) = error, let message = serverMessage else {
            return error.localizedDescription
        }
        switch message {
        case "finish_before_start": return "Смена не может закончиться раньше, чем началась."
        case "leadership_only":     return "Править смены может только руководство."
        case "not_checked_in":      return "У этого сотрудника нет открытой смены."
        case "not_finished":        return "Смена и так не завершена."
        default:                    return error.localizedDescription
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

    /// «старт · финиш» — обе точки открываются в картах. Словами, а не значками:
    /// 📍 и 🏁 рядом друг с другом читались как одно место.
    @ViewBuilder
    private func geoRow(_ shift: CheckinDTO) -> some View {
        let start = shift.geo_lat != nil && shift.geo_lng != nil
        let finish = shift.finish_lat != nil && shift.finish_lng != nil
        if start || finish {
            HStack(spacing: Spacing.xs) {
                if start {
                    geoLink("старт", lat: shift.geo_lat!, lng: shift.geo_lng!, color: Theme.success)
                }
                if finish {
                    geoLink("финиш", lat: shift.finish_lat!, lng: shift.finish_lng!,
                            color: shift.finishedFarAway ? Theme.danger : Theme.textSecondary)
                }
            }
        }
    }

    private func geoLink(_ title: String, lat: Double, lng: Double, color: Color) -> some View {
        Button {
            if let url = URL(string: "https://yandex.ru/maps/?pt=\(lng),\(lat)&z=17") { openURL(url) }
        } label: {
            Label(title, systemImage: "mappin.circle.fill")
                .font(.system(size: 10)).foregroundStyle(color)
        }
        .buttonStyle(.plain)
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
