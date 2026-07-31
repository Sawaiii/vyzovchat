import SwiftUI
import ImageIO

/// Кэш изображений в памяти (аватары, превью медиа) — быстрее и без мигания.
enum ImageMemoryCache {
    /// Полноразмерные изображения — для полноэкранного просмотра/зума.
    static let shared: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 120 * 1024 * 1024   // ~120 МБ
        return c
    }()

    /// Уменьшенные превью для аватаров/плиток в ленте — их держим отдельно, чтобы
    /// не подменять полноразмерные картинки в полноэкранном просмотре.
    static let thumbnails: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 60 * 1024 * 1024    // ~60 МБ
        return c
    }()

    /// Примерная «стоимость» картинки в байтах — для лимита кэша.
    static func cost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

    /// Ключ кэша — адрес объекта без подписи.
    ///
    /// Сервер подписывает ссылки заново каждые несколько часов. Если держать в
    /// ключе полный URL, весь кэш разом обнуляется и приложение снова выкачивает
    /// все картинки, хотя это ровно те же файлы.
    static func key(_ url: URL) -> NSURL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.query = nil
        return (comps?.url ?? url) as NSURL
    }
}

/// Декодирование/уменьшение картинок вне главного потока: полноразмерный декод
/// на главном потоке — главный источник джанка при скролле лент с фото.
enum ImageDecoding {
    /// Декодирует и уменьшает картинку до `maxPixel` по большей стороне.
    /// Работает через ImageIO без создания полноразмерного `UIImage`.
    static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOptions) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}

/// Очередь загрузки картинок.
///
/// В ленте с альбомами десятки плиток стартуют одновременно. Раньше они разом
/// уходили в общую сессию: соединения к хранилищу кончались, часть запросов
/// висела до таймаута, и приложение выглядело подвисшим. Пропускаем ограниченное
/// число одновременно — остальные ждут очереди, а не забивают сеть.
private actor ImageLoadQueue {
    static let shared = ImageLoadQueue()

    private let limit = 5
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
        running += 1
    }

    func release() {
        running -= 1
        if !waiting.isEmpty { waiting.removeFirst().resume() }
    }
}

/// Отдельная сессия под картинки со своим дисковым кэшем: они ходят в хранилище,
/// а не в наш API, и не должны конкурировать с ним за соединения.
private enum ImageSession {
    static let shared: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.httpMaximumConnectionsPerHost = 5
        cfg.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                diskCapacity: 400 * 1024 * 1024)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: cfg)
    }()
}

/// Замена AsyncImage с кэшированием в памяти + на диск (URLCache).
/// API совместим с формой AsyncImage(url:) { image } placeholder: { ... }.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    init(url: URL?,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        // Уже загруженное фото берём из кэша СРАЗУ (синхронно), а не через .task на
        // следующем кадре — иначе плейсхолдер мигал и высота ленты скакала при
        // прогрузке медиа, «дёргая» чат туда-сюда после открытия.
        _uiImage = State(initialValue: url.flatMap { ImageMemoryCache.thumbnails.object(forKey: ImageMemoryCache.key($0)) })
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        let key = ImageMemoryCache.key(url)
        if let cached = ImageMemoryCache.thumbnails.object(forKey: key) {
            uiImage = cached
            return
        }
        // Две попытки, а не четыре: при таймауте в 12 секунд четыре подряд давали
        // почти минуту висящих запросов на КАЖДУЮ плитку — приложение из-за этого
        // казалось зависшим. Один повтор закрывает случайный сбой, а безнадёжную
        // ссылку дальше долбить бессмысленно.
        for attempt in 0..<2 {
            if Task.isCancelled { return }

            await ImageLoadQueue.shared.acquire()
            let ok: Data? = await {
                defer { Task { await ImageLoadQueue.shared.release() } }
                guard let (data, resp) = try? await ImageSession.shared.data(from: url) else { return nil }
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
                return data
            }()

            if let data = ok {
                // Декод и уменьшение — в фоне, чтобы не морозить скролл.
                let img = await Task.detached(priority: .userInitiated) {
                    ImageDecoding.downsample(data: data, maxPixel: 1400)
                }.value
                if let img {
                    if Task.isCancelled { return }
                    ImageMemoryCache.thumbnails.setObject(img, forKey: key, cost: ImageMemoryCache.cost(img))
                    uiImage = img
                    return
                }
            }
            if Task.isCancelled || attempt == 1 { return }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }
}
