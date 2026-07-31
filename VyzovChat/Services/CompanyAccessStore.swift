import Foundation

/// Какие компании (бренды) скрыты у конкретного сотрудника.
///
/// Задаток на будущее: на сервере такого поля пока нет, поэтому список живёт
/// локально. Когда в API появится видимость компаний, менять надо только тело
/// этих методов — вызовы во вьюхах останутся прежними.
enum CompanyAccessStore {
    private static let key = "vyzovchat.hiddenCompanies"

    /// Словарь workerId → скрытые компании.
    private static var all: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func hidden(for workerId: String) -> Set<String> {
        Set(all[workerId] ?? [])
    }

    static func setHidden(_ companies: Set<String>, for workerId: String) {
        var map = all
        if companies.isEmpty { map.removeValue(forKey: workerId) }
        else { map[workerId] = Array(companies).sorted() }
        all = map
    }

    static func isHidden(_ company: String?, for workerId: String) -> Bool {
        guard let company else { return false }   // «без компании» видно всем
        return hidden(for: workerId).contains(company)
    }

    @discardableResult
    static func toggle(_ company: String, for workerId: String) -> Bool {
        var set = hidden(for: workerId)
        let nowHidden: Bool
        if set.contains(company) { set.remove(company); nowHidden = false }
        else { set.insert(company); nowHidden = true }
        setHidden(set, for: workerId)
        return nowHidden
    }
}
