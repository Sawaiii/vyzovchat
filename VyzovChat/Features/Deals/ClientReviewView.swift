import SwiftUI
import UIKit

/// Опрос клиента по итогам мероприятия.
///
/// Менеджер выдаёт разовую ссылку и отправляет её клиенту любым способом. Клиент
/// — не сотрудник, поэтому страницу опроса открывает браузер: приложение только
/// выдаёт ссылку и показывает, что пришло. Заполненный опрос падает врезкой в чат.
struct ClientReviewView: View {
    let dealId: String
    let eventTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var reviews: [ReviewDTO] = []
    @State private var isLoading = true
    @State private var creating = false
    @State private var errorText: String?
    /// Ссылка, которую только что скопировали, — кнопка говорит «Скопировано».
    @State private var copiedId: Int?

    /// Заполненные сверху: ради них экран и открывают.
    private var filled: [ReviewDTO] { reviews.filter(\.isFilled) }
    private var pending: [ReviewDTO] { reviews.filter { !$0.isFilled } }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            if let errorText { ErrorBanner(text: errorText) }
                            createCard
                            if !filled.isEmpty {
                                section("Отзывы", filled.map { AnyView(filledCard($0)) })
                            }
                            if !pending.isEmpty {
                                section("Выданные ссылки", pending.map { AnyView(linkCard($0)) })
                            }
                            if reviews.isEmpty {
                                Text("Ссылок пока нет. Выдайте первую — клиент откроет её в браузере.")
                                    .font(Typography.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle("Опрос клиента")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func section(_ title: String, _ cards: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            ForEach(Array(cards.enumerated()), id: \.offset) { $0.element }
        }
    }

    private var createCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(eventTitle).font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary).lineLimit(2)
                PrimaryButton(title: "Выдать ссылку", isLoading: creating, isEnabled: !creating) {
                    Task { await create() }
                }
                Text("Ссылка разовая: заполнить опрос по ней можно один раз. Четыре оценки, комментарий по желанию — результат придёт врезкой в чат.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Выданная, но ещё не заполненная ссылка.
    private func linkCard(_ review: ReviewDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(review.url)
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).textSelection(.enabled)
                HStack(spacing: Spacing.s) {
                    Button(copiedId == review.id ? "Скопировано" : "Копировать") {
                        UIPasteboard.general.string = review.url
                        copiedId = review.id
                        Haptics.success()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(copiedId == review.id ? Theme.success : Theme.accent)

                    if let url = URL(string: review.url) {
                        ShareLink(item: url) {
                            Label("Отправить", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("ждём ответа").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// Пришедший отзыв.
    private func filledCard(_ review: ReviewDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    if let avg = review.average {
                        Text(String(format: "%.1f", avg).replacingOccurrences(of: ".", with: ",") + " из 10")
                            .font(Typography.headline)
                            .foregroundStyle(avg >= 8 ? Theme.success : (avg >= 5 ? Theme.warning : Theme.danger))
                    }
                    Spacer()
                    Text(when(review.filled_at)).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                scoreRow("Работа команды", review.team)
                scoreRow("Работа старшего", review.senior)
                scoreRow("Качество оборудования", review.equipment)
                scoreRow("Вовлечённость менеджера", review.manager)
                if let comment = review.comment, !comment.isEmpty {
                    Text("«" + comment + "»")
                        .font(Typography.callout).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func scoreRow(_ title: String, _ score: Int?) -> some View {
        HStack(spacing: Spacing.s) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Spacing.xs)
            // Шкала закрашивается до выбранной оценки — как в вебе.
            HStack(spacing: 2) {
                ForEach(1...10, id: \.self) { i in
                    Capsule()
                        .fill(i <= (score ?? 0) ? Theme.accent : Theme.panel2)
                        .frame(width: 6, height: 8)
                }
            }
            Text("\(score ?? 0)").font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func when(_ iso: String?) -> String {
        guard let date = DateParse.iso(iso) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: date)
    }

    private func create() async {
        creating = true
        errorText = nil
        defer { creating = false }
        do {
            let created = try await PeopleExtras.createReview(dealId: dealId)
            UIPasteboard.general.string = created.url
            copiedId = created.id
            Haptics.success()
            await load()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func load() async {
        reviews = await PeopleExtras.reviews(dealId: dealId)
        isLoading = false
    }
}
