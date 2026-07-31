import SwiftUI
import AVKit

/// Обёртка для показа медиа через fullScreenCover(item:).
struct MediaPreview: Identifiable {
    let id = UUID()
    let items: [Message.Attachment]
    let index: Int
}

/// Полноэкранный просмотр медиа: листание влево/вправо + свайп вниз для закрытия.
/// Пока фото приближено — свайп вниз и листание отключены, жест двигает по фото.
struct MediaPager: View {
    let items: [Message.Attachment]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var dragY: CGFloat = 0
    @State private var isZoomed = false

    init(items: [Message.Attachment], startIndex: Int) {
        self.items = items
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backgroundOpacity).ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(items.indices, id: \.self) { i in
                    MediaPage(attachment: items[i],
                              isCurrent: i == index,
                              onZoomChanged: { z in if i == index { isZoomed = z } })
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
            .offset(y: dragY)
            // Свайп вниз для закрытия — только когда фото не приближено.
            .simultaneousGesture(isZoomed ? nil : dismissDrag)
            .onChange(of: index) { isZoomed = false }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline).foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { v in
                if abs(v.translation.height) > abs(v.translation.width) {
                    dragY = v.translation.height
                }
            }
            .onEnded { _ in
                if abs(dragY) > 140 { dismiss() }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragY = 0 } }
            }
    }

    private var backgroundOpacity: Double {
        max(0, 1 - Double(abs(dragY)) / 400)
    }
}

private struct MediaPage: View {
    let attachment: Message.Attachment
    let isCurrent: Bool
    let onZoomChanged: (Bool) -> Void

    @State private var uiImage: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    // Плеер создаём один раз (в body — новый AVPlayer на каждый рендер: перезапуск
    // с нуля + утечка предыдущего).
    @State private var player: AVPlayer?

    // Для панорамы приближение считаем по «зафиксированному» масштабу (после
    // отпускания щипка), чтобы прямо во время щипка вью не пересобиралась и не
    // срывала жест.
    private var isZoomed: Bool { lastScale > 1.01 }

    var body: some View {
        if attachment.isVideo, let url = attachment.remoteURL {
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { if player == nil { player = AVPlayer(url: url) } }
                .onDisappear { player?.pause() }
        } else if let url = attachment.remoteURL {
            GeometryReader { geo in
                photo(in: geo)
                    .task(id: url) { await load(url) }
                    .onChange(of: isCurrent) { if !isCurrent { resetZoom() } }
                    // Родителю (свайп-закрытие/листание) сообщаем по ЖИВОМУ масштабу,
                    // чтобы они отключались сразу с началом щипка, а не после его
                    // фиксации — иначе первый зум от 1× дёргает и листает страницу.
                    .onChange(of: scale) { onZoomChanged(scale > 1.01) }
            }
        }
    }

    /// Само фото с жестами. Кадр фиксируем на весь экран ДО навешивания жеста —
    /// тогда система координат жеста стабильна (geo.size, без трансформаций), и
    /// startLocation щипка совпадает с точкой на экране: зум идёт от места между
    /// пальцами, а не от центра. Панораму подключаем ТОЛЬКО когда фото приближено —
    /// иначе её жест перехватывал бы горизонтальный свайп и листание застревало.
    @ViewBuilder
    private func photo(in geo: GeometryProxy) -> some View {
        let img = imageContent
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { toggleZoom() }

        if isZoomed {
            // Приближено: масштаб и панораму ведёт ОДИН жест (щипок + перемещение
            // вместе). Раньше отдельная панорама-DragGesture дралась с щипком за
            // общий offset — из-за этого зум дёргался и «лагал». highPriority —
            // чтобы панорама била листание TabView.
            img.highPriorityGesture(zoomPanGesture(geo))
        } else {
            // Не приближено: только щипок (инициирует зум). Одиночные свайпы —
            // листание/закрытие через родителя.
            img.gesture(zoomGesture(geo))
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let uiImage {
            Image(uiImage: uiImage).resizable().scaledToFit()
        } else {
            ProgressView().tint(.white)
        }
    }

    private func zoomGesture(_ geo: GeometryProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = min(max(1, lastScale * value.magnification), 4)
                let ratio = newScale / lastScale
                // Точка щипка относительно центра экрана (координаты стабильны, т.к.
                // жест на нетрансформированном кадре размера geo).
                let dx = value.startLocation.x - geo.size.width / 2
                let dy = value.startLocation.y - geo.size.height / 2
                // Держим точку щипка на месте: зум идёт от места между пальцами.
                // offset' = ratio*offset − (ratio−1)*d, где d — точка относительно центра.
                offset = CGSize(width: ratio * lastOffset.width - (ratio - 1) * dx,
                                height: ratio * lastOffset.height - (ratio - 1) * dy)
                scale = newScale
            }
            .onEnded { _ in
                if scale <= 1.01 {
                    withAnimation(.smooth(duration: 0.2)) { resetZoom() }
                } else {
                    lastScale = scale
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        clampOffset(geo)
                    }
                }
            }
    }

    /// Приближено: щипок (масштаб от места между пальцами) и перемещение (панорама)
    /// в одном жесте — оба меняют общий offset согласованно, поэтому движение плавное.
    private func zoomPanGesture(_ geo: GeometryProxy) -> some Gesture {
        SimultaneousGesture(MagnifyGesture(), DragGesture())
            .onChanged { value in
                var newScale = scale
                var newOffset = lastOffset
                if let mag = value.first {
                    newScale = min(max(1, lastScale * mag.magnification), 4)
                    let ratio = newScale / lastScale
                    let dx = mag.startLocation.x - geo.size.width / 2
                    let dy = mag.startLocation.y - geo.size.height / 2
                    newOffset = CGSize(width: ratio * lastOffset.width - (ratio - 1) * dx,
                                       height: ratio * lastOffset.height - (ratio - 1) * dy)
                }
                if let drag = value.second {
                    newOffset.width += drag.translation.width
                    newOffset.height += drag.translation.height
                }
                scale = newScale
                // За краем движение вязнет, а не упирается: без этого фото уезжало
                // сколько угодно и на отпускании отскакивало рывком.
                offset = rubberBanded(newOffset, scale: newScale, in: geo)
            }
            .onEnded { _ in
                if scale <= 1.01 {
                    withAnimation(.smooth(duration: 0.2)) { resetZoom() }
                } else {
                    lastScale = scale
                    // Возврат из-за края — пружиной, а не мгновенной обрезкой.
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        clampOffset(geo)
                    }
                }
            }
    }

    /// Сопротивление за краем — как в системной галерее: чем дальше утащили,
    /// тем меньше фото поддаётся.
    private func rubberBanded(_ value: CGSize, scale: CGFloat, in geo: GeometryProxy) -> CGSize {
        let fitted = fittedSize(in: geo)
        let maxX = max(0, (fitted.width * scale - geo.size.width) / 2)
        let maxY = max(0, (fitted.height * scale - geo.size.height) / 2)
        return CGSize(width: band(value.width, limit: maxX, dimension: geo.size.width),
                      height: band(value.height, limit: maxY, dimension: geo.size.height))
    }

    private func band(_ value: CGFloat, limit: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0, abs(value) > limit else { return value }
        let over = abs(value) - limit
        let damped = (1 - 1 / (over / dimension * 0.55 + 1)) * dimension
        return (value < 0 ? -1 : 1) * (limit + damped)
    }

    private func toggleZoom() {
        withAnimation(.smooth(duration: 0.25)) {
            if isZoomed {
                resetZoom()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    /// Реальный размер фото на экране (scaledToFit), а не размер контейнера —
    /// иначе кламп разрешал бы утащить портретное фото в чёрные поля по бокам.
    private func fittedSize(in geo: GeometryProxy) -> CGSize {
        guard let ui = uiImage, ui.size.width > 0, ui.size.height > 0 else { return geo.size }
        let s = min(geo.size.width / ui.size.width, geo.size.height / ui.size.height)
        return CGSize(width: ui.size.width * s, height: ui.size.height * s)
    }

    /// Не даём утащить фото за край: сдвиг ограничен «выступающей» частью
    /// (реальный размер фото × масштаб минус экран).
    private func clampOffset(_ geo: GeometryProxy) {
        let fitted = fittedSize(in: geo)
        let maxX = max(0, (fitted.width * scale - geo.size.width) / 2)
        let maxY = max(0, (fitted.height * scale - geo.size.height) / 2)
        offset = CGSize(width: min(max(offset.width, -maxX), maxX),
                        height: min(max(offset.height, -maxY), maxY))
        lastOffset = offset
    }

    private func resetZoom() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }

    /// Предел стороны декодированного снимка (в пикселях).
    private static let maxDecodedSide: CGFloat = 3000

    private func load(_ url: URL) async {
        if let cached = ImageMemoryCache.shared.object(forKey: ImageMemoryCache.key(url)) {
            uiImage = cached
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
        // Декод — в фоне (на главном потоке он морозит открытие). Заодно ужимаем
        // до разумной стороны: снимок с телефона бывает на 12 мегапикселей, и при
        // зуме система пересчитывала его целиком каждый кадр — отсюда рывки.
        // 3000 px хватает с запасом даже на четырёхкратном приближении.
        let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let raw = UIImage(data: data) else { return nil }
            let side = max(raw.size.width, raw.size.height) * raw.scale
            guard side > Self.maxDecodedSide else { return raw.preparingForDisplay() }
            let k = Self.maxDecodedSide / side
            let target = CGSize(width: raw.size.width * raw.scale * k,
                                height: raw.size.height * raw.scale * k)
            return raw.preparingThumbnail(of: target) ?? raw.preparingForDisplay()
        }.value
        guard let img, !Task.isCancelled else { return }
        ImageMemoryCache.shared.setObject(img, forKey: ImageMemoryCache.key(url), cost: ImageMemoryCache.cost(img))
        uiImage = img
    }
}
