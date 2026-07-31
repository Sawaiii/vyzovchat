import SwiftUI
import UIKit

/// Оформление системных элементов (навбар, таббар, поиск, сегменты) под тёмную
/// тему Telegram — вместо стандартных полупрозрачных эпловских.
enum AppAppearance {
    static func apply() {
        let panel = UIColor(Theme.panel)
        let panel2 = UIColor(Theme.panel2)
        let text = UIColor(Theme.textPrimary)
        let muted = UIColor(Theme.textSecondary)
        let accent = UIColor(Theme.accent)

        // Навигационная панель
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = panel
        nav.shadowColor = UIColor(Theme.line)
        nav.titleTextAttributes = [.foregroundColor: text]
        nav.largeTitleTextAttributes = [.foregroundColor: text]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = accent

        // Таб-бар
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = panel
        tab.shadowColor = UIColor(Theme.line)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = muted

        // Поиск
        UISearchBar.appearance().tintColor = accent
        UISearchBar.appearance().barTintColor = panel
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).textColor = text

        // Сегменты (Мероприятия / Личные / Архив)
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = accent
        seg.backgroundColor = panel2
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: muted], for: .normal)

        // Таблицы/списки — прозрачный фон, чтобы был виден наш градиент
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
    }
}
