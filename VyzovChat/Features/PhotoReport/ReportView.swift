import SwiftUI
import PhotosUI

/// Отчёт по мероприятию (только админ чата): отмечаем фото из чата и выгружаем
/// в папки мероприятия — «Отчёт», «Фотобанк». Отдельно — «Юридическая инфа» (файл).
struct ReportView: View {
    @ObservedObject var model: ChatViewModel
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var busy: String?
    @State private var resultText: String?
    @State private var errorText: String?
    @State private var showDocuments = false
    @State private var showClaims = false

    private let grid = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            hint
                            if model.reportPhotos.isEmpty {
                                EmptyState(icon: "photo.on.rectangle",
                                           title: "В чате нет фото",
                                           message: "Отчёт собирается из фотографий, присланных в этот чат.")
                                    .frame(maxWidth: .infinity)
                            } else {
                                LazyVGrid(columns: grid, spacing: 8) {
                                    ForEach(model.reportPhotos) { photo in
                                        cell(photo)
                                    }
                                }
                            }
                        }
                        .padding(Spacing.m)
                    }
                    bottomBar
                }
            }
            .navigationTitle("Отчёт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                if !model.pickedIds.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Снять отбор") { model.clearPicks() }
                    }
                }
            }
            .sheet(isPresented: $showDocuments) {
                EventDocumentsView(dealId: model.chat.dealId, isChatAdmin: model.isChatAdmin)
                    .environmentObject(session)
            }
            .sheet(isPresented: $showClaims) {
                ClaimsView(dealId: model.chat.dealId, isChatAdmin: model.isChatAdmin,
                           claimTopicId: model.claimTopicId)
                    .environmentObject(session)
            }
        }
    }

    private var hint: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle").foregroundStyle(Theme.accent)
            Text("Отметьте фото — они уйдут в папку мероприятия. Отмечено: \(model.pickedIds.count)")
                .font(Typography.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private func cell(_ photo: ChatViewModel.ReportPhoto) -> some View {
        let picked = model.pickedIds.contains(photo.id)
        return Button {
            model.togglePick(photo.id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    CachedAsyncImage(url: photo.url) { $0.resizable().scaledToFill() } placeholder: {
                        Theme.panel2
                    }
                )
                .overlay(alignment: .bottom) {
                    // Мероприятие с запретом — предупреждение на каждом кадре,
                    // чтобы его не отправили в фотобанк по невнимательности.
                    if model.chat.photosRestricted {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill").font(.system(size: 8))
                            Text("НЕЛЬЗЯ ИСПОЛЬЗОВАТЬ")
                                .font(.system(size: 8, weight: .bold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Theme.danger)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(picked ? Theme.accent : .white.opacity(0.9))
                    .background(Circle().fill(.black.opacity(0.25)))
                    .padding(6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(picked ? Theme.accent : .clear, lineWidth: 2.5)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.xs) {
            if let errorText { ErrorBanner(text: errorText) }
            if let resultText {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    Text(resultText).font(Typography.callout).foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }

            PrimaryButton(title: "Отправить отчёт", icon: "paperplane.fill",
                          isLoading: busy == "report",
                          isEnabled: !model.pickedIds.isEmpty && busy == nil) {
                run("report", label: "Отчёт отправлен")
            }

            // Тот же набор действий, что и в вебе: фотобанк, документы,
            // претензия и юр-инфо рядом с отправкой отчёта.
            HStack(spacing: Spacing.s) {
                SecondaryButton(title: "Фотобанк", icon: "photo.stack") {
                    run("photobank", label: "Выгружено в фотобанк")
                }
                .disabled(model.pickedIds.isEmpty || busy != nil)
                .opacity(model.pickedIds.isEmpty || busy != nil ? 0.5 : 1)

                SecondaryButton(title: busy == "legal" ? "Отправка…" : "Юр-инфо",
                                icon: "mappin.and.ellipse") {
                    uploadLegal()
                }
                .disabled(model.pickedIds.isEmpty || busy != nil)
                .opacity(model.pickedIds.isEmpty || busy != nil ? 0.5 : 1)
            }

            HStack(spacing: Spacing.s) {
                SecondaryButton(title: "Документы", icon: "doc.text") { showDocuments = true }
                SecondaryButton(title: "Претензия", icon: "exclamationmark.triangle") { showClaims = true }
            }
        }
        .padding(Spacing.m)
        .background(Theme.panel)
    }

    private func run(_ kind: String, label: String) {
        busy = kind
        errorText = nil
        resultText = nil
        Task {
            do {
                let res = try await model.exportPicked(to: kind)
                resultText = "\(label): \(res.count ?? 0) фото"
                Haptics.success()
            } catch {
                errorText = error.localizedDescription
                Haptics.warning()
            }
            busy = nil
        }
    }

    /// Юр. инфа: отмеченные фото из чата уходят в папку legal с нанесённой
    /// геометкой и временем съёмки (галерея больше не открывается).
    private func uploadLegal() {
        busy = "legal"
        errorText = nil
        resultText = nil
        Task {
            do {
                let result = try await model.exportLegal()
                resultText = result.withGeo == result.sent
                    ? "В «Юр. инфу»: \(result.sent) фото с геометкой"
                    : "В «Юр. инфу»: \(result.sent) фото (с координатами — \(result.withGeo))"
                Haptics.success()
            } catch {
                errorText = error.localizedDescription
                Haptics.warning()
            }
            busy = nil
        }
    }
}
