import Foundation

/// Локальный список чатов «без звука» (по id чата).
enum MuteStore {
    private static let key = "vyzovchat.mutedChats"

    static var muted: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }

    static func isMuted(_ chatId: String) -> Bool { muted.contains(chatId) }

    @discardableResult
    static func toggle(_ chatId: String) -> Bool {
        var set = muted
        let nowMuted: Bool
        if set.contains(chatId) { set.remove(chatId); nowMuted = false }
        else { set.insert(chatId); nowMuted = true }
        muted = set
        return nowMuted
    }
}
