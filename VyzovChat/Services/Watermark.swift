import UIKit

/// Нанесение юридической метки на фото: координаты + дата/время съёмки.
/// Веб рисует такую же метку перед отправкой в «Юридическую инфу».
enum Watermark {
    /// - Parameters:
    ///   - title: название мероприятия (из чата)
    ///   - geo: координаты, если есть
    ///   - address: полный адрес по координатам
    ///   - date: дата/время загрузки
    static func stamp(_ image: UIImage,
                      title: String? = nil,
                      geo: (lat: Double, lng: Double)?,
                      address: String? = nil,
                      date: Date = Date()) -> UIImage {
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = image.scale
            f.opaque = true
            return f
        }())

        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))

            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "dd.MM.yyyy HH:mm"

            // Строки метки: мероприятие, дата/время загрузки, координаты.
            var lines: [String] = []
            if let title, !title.isEmpty { lines.append(title) }
            lines.append("Загружено: " + df.string(from: date))
            if let address, !address.isEmpty { lines.append(address) }
            if let geo {
                lines.append(String(format: "Координаты: %.5f, %.5f", geo.lat, geo.lng))
            } else {
                lines.append("Координаты: нет данных")
            }

            // Размер шрифта — от ширины фото, чтобы метка читалась на любом снимке.
            let fontSize = max(13, size.width * 0.024)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]

            let lineHeight = fontSize * 1.3
            let widest = lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
            let pad = fontSize * 0.6
            let boxHeight = lineHeight * CGFloat(lines.count) + pad
            let box = CGRect(x: pad,
                             y: size.height - boxHeight - pad,
                             width: widest + pad * 2,
                             height: boxHeight)

            // Подложка, чтобы текст читался на любом фоне.
            UIColor.black.withAlphaComponent(0.5).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: fontSize * 0.35).fill()

            for (i, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: CGPoint(x: box.minX + pad, y: box.minY + pad * 0.5 + lineHeight * CGFloat(i)),
                    withAttributes: attrs)
            }
            _ = ctx
        }
    }
}
