import SwiftUI

/// Галерея чата: все фото и видео мероприятия одним экраном.
struct ChatGalleryView: View {
    let items: [Message.Attachment]
    @Environment(\.dismiss) private var dismiss
    @State private var preview: MediaPreview?

    private let grid = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if items.isEmpty {
                    EmptyState(icon: "photo.on.rectangle",
                               title: "Пока нет медиа",
                               message: "Здесь появятся все фото и видео из этого чата.")
                } else {
                    ScrollView {
                        LazyVGrid(columns: grid, spacing: 6) {
                            ForEach(items) { att in cell(att) }
                        }
                        .padding(Spacing.m)
                    }
                }
            }
            .navigationTitle("Галерея (\(items.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .fullScreenCover(item: $preview) { p in
                MediaPager(items: p.items, startIndex: p.index)
            }
        }
    }

    private func cell(_ att: Message.Attachment) -> some View {
        Button {
            let idx = items.firstIndex { $0.id == att.id } ?? 0
            preview = MediaPreview(items: items, index: idx)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    CachedAsyncImage(url: att.remoteURL) { $0.resizable().scaledToFill() } placeholder: {
                        Theme.panel2
                    }
                )
                .overlay {
                    if att.isVideo {
                        Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
