import SwiftUI

/// Социальная часть карточки человека: награды, оценка и компетенции.
///
/// Считается на сервере на месте и к правкам карточки отношения не имеет,
/// поэтому живёт отдельным блоком и грузится своим запросом: без него карточка
/// всё равно полезна.
struct ProfileExtrasSection: View {
    let user: User
    /// Себя не оценивают — у своей карточки блок только показывает.
    @EnvironmentObject private var session: AppSession

    @State private var extra: ProfileExtraDTO?
    @State private var skills: [String] = []
    @State private var rating: RatingDTO?
    @State private var newSkill = ""
    @State private var suggestions: [String] = []
    @State private var busy = false
    /// Награда, открытая крупно.
    @State private var shown: AchievementDTO?

    private var canRate: Bool { extra?.can_rate ?? false }
    private var achievements: [AchievementDTO] { extra?.achievements ?? [] }

    var body: some View {
        VStack(spacing: Spacing.m) {
            if rating != nil || canRate { ratingCard }
            if !achievements.isEmpty { awardsCard }
            if !skills.isEmpty || canRate { skillsCard }
        }
        .task { await load() }
        .sheet(item: $shown) { award in
            AwardDetailView(award: award)
        }
    }

    // MARK: - Оценка

    private var ratingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text("Оценка").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let text = rating?.text {
                        Text(text).font(Typography.callout.weight(.semibold))
                            .foregroundStyle(Theme.warning)
                    } else {
                        Text("нет оценок").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                if canRate {
                    HStack(spacing: Spacing.xs) {
                        ForEach(1...5, id: \.self) { star in
                            Button { Task { await rate(star) } } label: {
                                Image(systemName: star <= (rating?.mine ?? 0) ? "star.fill" : "star")
                                    .font(.title3)
                                    .foregroundStyle(star <= (rating?.mine ?? 0) ? Theme.warning : Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                        Spacer()
                        // Повторное нажатие на свою же звезду ничего не снимает —
                        // для этого отдельная кнопка, иначе оценку теряют случайно.
                        if (rating?.mine ?? 0) > 0 {
                            Button("Убрать") { Task { await rate(0) } }
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text("Вашу оценку видит только среднее — кто как поставил, в карточке не показывается.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Награды

    private var awardsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Награды").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3),
                          spacing: Spacing.s) {
                    ForEach(achievements) { award in
                        Button { shown = award } label: { AwardBadge(award: award) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Компетенции

    private var skillsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Что умеет").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                if skills.isEmpty {
                    Text("Компетенции не проставлены.")
                        .font(Typography.caption).foregroundStyle(Theme.textSecondary)
                }
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(skills, id: \.self) { skill in
                        HStack(spacing: 4) {
                            Text(skill).font(.footnote)
                            if canRate {
                                Button { Task { await removeSkill(skill) } } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.panel2, in: Capsule())
                    }
                }
                if canRate { skillEditor }
            }
        }
    }

    private var skillEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                TextField("Добавить компетенцию", text: $newSkill)
                    .padding(.horizontal, Spacing.s).padding(.vertical, 8)
                    .background(Theme.panel2, in: Capsule())
                    .onChange(of: newSkill) { Task { await loadSuggestions() } }
                Button { Task { await addSkill(newSkill) } } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                        .foregroundStyle(canAdd ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd || busy)
            }
            // Подсказки из уже проставленного: иначе «электрика», «Электрика» и
            // «электрик» расползаются по справочнику тремя разными метками.
            if !suggestions.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(suggestions.prefix(8), id: \.self) { hint in
                        Button { Task { await addSkill(hint) } } label: {
                            Text(hint).font(.caption2).foregroundStyle(Theme.accent)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var canAdd: Bool { !newSkill.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Данные

    private func load() async {
        extra = await PeopleExtras.profile(workerId: user.id)
        skills = extra?.skills ?? []
        rating = extra?.rating
    }

    private func rate(_ stars: Int) async {
        busy = true
        defer { busy = false }
        rating = try? await PeopleExtras.rate(workerId: user.id, stars: stars)
        Haptics.selection()
    }

    private func addSkill(_ skill: String) async {
        let value = skill.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        busy = true
        defer { busy = false }
        if let list = try? await PeopleExtras.addSkill(workerId: user.id, skill: value) {
            skills = list
            newSkill = ""
            suggestions = []
            Haptics.success()
        }
    }

    private func removeSkill(_ skill: String) async {
        busy = true
        defer { busy = false }
        if let list = try? await PeopleExtras.removeSkill(workerId: user.id, skill: skill) {
            skills = list
            Haptics.selection()
        }
    }

    private func loadSuggestions() async {
        let query = newSkill.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            suggestions = []
            return
        }
        let found = await PeopleExtras.skillSuggestions(query: query)
        suggestions = found.filter { !skills.contains($0) }
    }
}

/// Значок награды.
///
/// Гербы лежат картинками на сервере и раздаются веб-версией; тянуть их в
/// приложение незачем — рисуем свой значок по коду награды, а название и живое
/// число берём с сервера.
struct AwardBadge: View {
    let award: AchievementDTO

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(AwardStyle.color(award.code).opacity(0.18))
                Image(systemName: AwardStyle.icon(award.code))
                    .font(.title3).foregroundStyle(AwardStyle.color(award.code))
            }
            .frame(width: 56, height: 56)
            Text(award.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Награда крупно — с живым числом под ней.
struct AwardDetailView: View {
    let award: AchievementDTO
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: Spacing.m) {
                    ZStack {
                        Circle().fill(AwardStyle.color(award.code).opacity(0.18))
                        Image(systemName: AwardStyle.icon(award.code))
                            .font(.system(size: 60)).foregroundStyle(AwardStyle.color(award.code))
                    }
                    .frame(width: 160, height: 160)
                    Text(award.title).font(Typography.title)
                        .foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    Text(award.note).font(Typography.callout)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(Spacing.xl)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// Как выглядит награда: значок и цвет по коду с сервера.
enum AwardStyle {
    static func icon(_ code: String) -> String {
        switch code {
        case "trips":     return "car.fill"
        case "shift":     return "clock.fill"
        case "month":     return "calendar"
        case "photo":     return "camera.fill"
        case "orders":    return "briefcase.fill"
        case "brigade":   return "person.3.fill"
        case "store":     return "shippingbox.fill"
        case "years":     return "rosette"
        case "on_time":   return "alarm.fill"
        case "night":     return "moon.stars.fill"
        case "self":      return "person.fill.checkmark"
        case "reads":     return "text.book.closed.fill"
        case "no_claims": return "hand.thumbsup.fill"
        default:          return "star.fill"
        }
    }

    static func color(_ code: String) -> Color {
        switch code {
        case "trips", "month", "orders": return Theme.accent
        case "shift", "night":           return Color(hex: 0x9B8CFF)
        case "photo", "store":           return Theme.warning
        case "brigade", "self":          return Theme.success
        case "years", "on_time":         return Color(hex: 0xE0B341)
        default:                         return Theme.success
        }
    }
}
