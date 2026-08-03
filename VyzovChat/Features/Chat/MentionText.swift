import SwiftUI

/// Текст сообщения с кликабельными упоминаниями «@Фамилия Имя».
///
/// Собираем одним `Text` со ссылками, а не набором кнопок: пузырь ловит долгое
/// нажатие для меню сообщения, и вложенные кнопки его съедали бы — по той же
/// причине здесь не Button, что и у ника с цитатой.
enum MentionText {
    /// Своя схема: настоящих адресов у упоминаний нет, ссылку перехватывает сам
    /// пузырь и открывает профиль.
    static let scheme = "vyzovmention"

    static func workerId(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return url.host
    }

    /// Подсвечивает те упоминания, за которыми стоит известный нам человек.
    ///
    /// «@все» остаётся обычным текстом: за ним нет человека, открывать нечего.
    /// Незнакомое имя тоже не трогаем — ссылка в никуда хуже простого текста.
    ///
    /// - Parameter people: ФИО в нижнем регистре → id сотрудника.
    static func build(_ text: String, people: [String: String], color: Color) -> AttributedString {
        guard !people.isEmpty, text.contains("@") else { return AttributedString(text) }

        var out = AttributedString()
        var cursor = text.startIndex

        while let at = text[cursor...].firstIndex(of: "@") {
            // «@» должна начинать слово, иначе это почта или часть слова.
            let startsWord = at == text.startIndex
                || text[text.index(before: at)].isWhitespace
                || text[text.index(before: at)] == "("
            let nameStart = text.index(after: at)

            guard startsWord, nameStart < text.endIndex,
                  let match = longestName(in: text[nameStart...], among: people) else {
                // Не упоминание — переносим как есть и идём дальше за следующей «@».
                out.append(AttributedString(text[cursor...at]))
                cursor = nameStart
                continue
            }

            out.append(AttributedString(text[cursor..<at]))
            let end = text.index(nameStart, offsetBy: match.name.count)
            var mention = AttributedString(text[at..<end])
            mention.foregroundColor = color
            mention.link = URL(string: "\(scheme)://\(match.id)")
            out.append(mention)
            cursor = end
        }

        out.append(AttributedString(text[cursor...]))
        return out
    }

    /// Самое длинное подходящее ФИО: «Иванов» и «Иванов Пётр» могут оба быть в
    /// составе, и обрывать на коротком нельзя — упоминали-то полное.
    private static func longestName(in tail: Substring,
                                    among people: [String: String]) -> (name: String, id: String)? {
        let lowered = tail.lowercased()
        var best: (name: String, id: String)?
        for (name, id) in people where lowered.hasPrefix(name) {
            // Имя должно кончаться на границе слова, иначе «@Иван» подсветится
            // внутри «@Иванов».
            let after = lowered.index(lowered.startIndex, offsetBy: name.count)
            if after < lowered.endIndex {
                let next = lowered[after]
                guard next.isWhitespace || next.isPunctuation else { continue }
            }
            if best == nil || name.count > best!.name.count { best = (name, id) }
        }
        return best
    }
}
