import CoreGraphics

/// Раскладка альбома фото «как в Telegram»: несколько фото одной отправкой рисуются
/// мозаикой без пустых ячеек. Если известны реальные пропорции всех фото (пришли из
/// БД — img_w/img_h), раскладываем ПО ПРОПОРЦИЯМ: ширины в ряду пропорциональны
/// аспектам, ряд имеет общую высоту (точь-в-точь телеграм-вид). Если размеров нет
/// (старые фото), падаем на раскладку ПО КОЛИЧЕСТВУ (ячейки близки к квадрату).
enum AlbumMosaicLayout {
    /// `aspects` — отношение ширина/высота каждого фото (или nil/0, если неизвестно).
    static func frames(aspects: [CGFloat]?, count: Int,
                       width W: CGFloat, spacing sp: CGFloat = 2) -> (size: CGSize, rects: [CGRect]) {
        guard count > 1 else {
            return (CGSize(width: W, height: W), [CGRect(x: 0, y: 0, width: W, height: W)])
        }
        if let aspects, aspects.count == count, aspects.allSatisfy({ $0 > 0 }) {
            return aspectFrames(aspects, W, sp)
        }
        return countFrames(count, W, sp)
    }

    // MARK: - По пропорциям (есть размеры)

    private static func aspectFrames(_ aspects: [CGFloat], _ W: CGFloat, _ sp: CGFloat) -> (CGSize, [CGRect]) {
        var rects: [CGRect] = []
        var y: CGFloat = 0
        var idx = 0
        for k in rowSplit(aspects.count) {
            let rowA = Array(aspects[idx..<idx + k])
            let avail = W - CGFloat(k - 1) * sp
            // Общая высота ряда: avail = H * Σaspect. Ограничиваем разумными пределами.
            var H = avail / max(0.1, rowA.reduce(0, +))
            H = min(max(H, 90), k == 1 ? 260 : 250)
            // Ширины по аспектам, нормируем чтобы точно заполнить ряд.
            var widths = rowA.map { $0 * H }
            let sw = widths.reduce(0, +)
            if sw > 0 { let f = avail / sw; widths = widths.map { $0 * f } }
            let h = H.rounded()
            var x: CGFloat = 0
            for w in widths {
                rects.append(CGRect(x: x, y: y, width: w, height: h))
                x += w + sp
            }
            y += h + sp
            idx += k
        }
        return (CGSize(width: W, height: max(0, y - sp)), rects)
    }

    /// Сколько фото в каждом ряду (для раскладки по пропорциям).
    private static func rowSplit(_ n: Int) -> [Int] {
        switch n {
        case 2:  return [2]
        case 3:  return [1, 2]
        case 4:  return [2, 2]
        case 5:  return [2, 3]
        case 6:  return [3, 3]
        case 7:  return [2, 2, 3]
        case 8:  return [3, 3, 2]
        case 9:  return [3, 3, 3]
        case 10: return [3, 3, 4]
        default:
            var rows: [Int] = []
            var m = n
            while m > 4 { rows.append(3); m -= 3 }
            rows.append(m)
            return rows
        }
    }

    // MARK: - По количеству (размеров нет)

    private static func countFrames(_ count: Int, _ W: CGFloat, _ sp: CGFloat) -> (CGSize, [CGRect]) {
        switch count {
        case 2:  return rows([2], W, sp)
        case 3:  return threeLayout(W, sp)
        case 4:  return rows([2, 2], W, sp)
        case 5:  return rows([2, 3], W, sp)
        case 6:  return rows([3, 3], W, sp)
        case 7:  return rows([2, 2, 3], W, sp)
        case 8:  return rows([3, 3, 2], W, sp)
        case 9:  return rows([3, 3, 3], W, sp)
        case 10: return rows([3, 3, 4], W, sp)
        default:
            var rowCounts: [Int] = []
            var n = count
            while n > 4 { rowCounts.append(3); n -= 3 }
            rowCounts.append(n)
            return rows(rowCounts, W, sp)
        }
    }

    /// Ряды квадратных ячеек: ряд с меньшим числом фото — выше.
    private static func rows(_ rowCounts: [Int], _ W: CGFloat, _ sp: CGFloat) -> (CGSize, [CGRect]) {
        var rects: [CGRect] = []
        var y: CGFloat = 0
        for k in rowCounts {
            let cellW = (W - CGFloat(k - 1) * sp) / CGFloat(k)
            let h = cellW.rounded()
            var x: CGFloat = 0
            for _ in 0..<k {
                rects.append(CGRect(x: x, y: y, width: cellW, height: h))
                x += cellW + sp
            }
            y += h + sp
        }
        return (CGSize(width: W, height: max(0, y - sp)), rects)
    }

    /// 3 фото без размеров: одно большое слева, два стопкой справа.
    private static func threeLayout(_ W: CGFloat, _ sp: CGFloat) -> (CGSize, [CGRect]) {
        let rightW = (W * 0.34).rounded()
        let leftW = W - sp - rightW
        let rightH = ((leftW - sp) / 2).rounded()
        let H = rightH * 2 + sp
        return (CGSize(width: W, height: H), [
            CGRect(x: 0, y: 0, width: leftW, height: H),
            CGRect(x: leftW + sp, y: 0, width: rightW, height: rightH),
            CGRect(x: leftW + sp, y: rightH + sp, width: rightW, height: rightH)
        ])
    }
}
