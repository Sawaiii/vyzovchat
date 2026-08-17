import XCTest

/// Снимает экраны приложения в симуляторе — из этих кадров собирается презентация.
///
/// Запускается только в CI (`.github/workflows/screenshots.yml`): на Windows
/// симулятора нет, а на раннере macOS есть. Логин и пароль тестового сотрудника
/// приходят из секретов репозитория — `xcodebuild` пробрасывает переменные с
/// префиксом `TEST_RUNNER_` в процесс теста, снимая префикс.
///
/// Тест намеренно не падает, если экран не открылся: кадры собираем «сколько
/// получилось», а чего не хватило — видно по списку вложений в отчёте. Падение
/// на третьем экране обесценило бы восемь снятых до него.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    /// Системные диалоги (уведомления, геопозиция) рисует не приложение, а оболочка —
    /// и искать их надо в ней, иначе для теста их будто и нет.
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Порядковый номер кадра: имя файла задаёт порядок в презентации.
    private var shotIndex = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // Симулятор в CI поднимается с английской системой — просим приложение
        // и системные диалоги говорить по-русски, иначе на кадрах окажется смесь.
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        watchSystemAlerts()
        // Разрешение на уведомления приложение просит прямо на старте — диалог
        // накрыл бы экран входа, поэтому закрываем его до первого кадра.
        dismissSystemAlerts(waiting: 10)
    }

    func testCaptureScreens() throws {
        signIn()

        // Чаты — стартовая вкладка.
        wait(for: "Чаты")
        snap("chats-list")
        openFirstRow()
        snap("chat-conversation")

        // Смены мероприятия — кнопка в панели переписки.
        if tapButton("Смены") {
            snap("shifts")
            closeSheet()
        }

        // Остальное спрятано в меню «…» справа в панели.
        if openChatMenu(), tapButton("Медиа чата") {
            snap("chat-media")
            closeSheet()
        }
        if openChatMenu(), tapButton("Участники") {
            snap("chat-members")
            closeSheet()
        }

        goBack()

        // Заказы.
        tapTab("Заказы")
        snap("deals-list")
        openFirstRow()
        snap("deal-detail")
        goBack()

        // Отчёты — вкладка только у руководителя; у рядового сотрудника её нет.
        if tapTab("Отчёты") {
            snap("dashboard")
        }

        // Диск.
        tapTab("Диск")
        snap("disk")

        // Профиль.
        tapTab("Профиль")
        snap("profile")
    }

    // MARK: - Вход

    private func signIn() {
        // Первым идёт приветственный экран, поля появляются только после «Войти».
        let welcome = app.buttons["Войти"].firstMatch
        if welcome.waitForExistence(timeout: 30), !app.textFields["Логин"].exists {
            snap("welcome")
            welcome.tap()
        }

        let login = app.textFields["Логин"]
        guard login.waitForExistence(timeout: 20) else {
            XCTFail("Экран входа не открылся — снимать дальше нечего")
            return
        }
        snap("login")

        guard let user = secret("DEMO_LOGIN"), let pass = secret("DEMO_PASSWORD") else {
            XCTFail("Нет DEMO_LOGIN/DEMO_PASSWORD: без учётной записи внутрь приложения не попасть")
            return
        }

        login.tap()
        login.typeText(user)

        let password = app.secureTextFields["Пароль"]
        if password.waitForExistence(timeout: 5) {
            password.tap()
            password.typeText(pass)
        }

        app.buttons["Войти"].firstMatch.tap()

        // Вошли — это видно по полосе вкладок. Если её нет, дальше снимать нечего:
        // пусть прогон покраснеет здесь, а не отдаст десяток одинаковых кадров.
        let chatsTab = app.buttons["Чаты"].firstMatch
        XCTAssertTrue(chatsTab.waitForExistence(timeout: 60),
                      "Вход не прошёл: список чатов не появился")
    }

    /// Значение секрета. `xcodebuild` отдаёт его без префикса, но на всякий
    /// случай смотрим и полное имя — так тест переживёт запуск из Xcode.
    private func secret(_ name: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        let value = env[name] ?? env["TEST_RUNNER_" + name]
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Навигация

    /// Ждём появления надписи — признак того, что экран дорисовался.
    @discardableResult
    private func wait(for label: String, timeout: TimeInterval = 30) -> Bool {
        let element = app.staticTexts[label].firstMatch
        return element.waitForExistence(timeout: timeout)
    }

    /// Переключает вкладку. Возвращает `false`, если такой вкладки нет —
    /// у рядового сотрудника, например, нет «Отчётов».
    @discardableResult
    private func tapTab(_ title: String) -> Bool {
        let tab = app.buttons[title].firstMatch
        guard tab.waitForExistence(timeout: 10), tab.isHittable else { return false }
        tab.tap()
        settle()
        return true
    }

    /// Открывает первую строку списка. Ячейки здесь — не системный `List`,
    /// а свои кнопки в `LazyVStack`, поэтому ищем по кнопкам внутри прокрутки
    /// и берём верхнюю из тех, что не относятся к полосе вкладок.
    private func openFirstRow() {
        let tabTitles: Set<String> = ["Чаты", "Заказы", "Отчёты", "Диск", "Профиль"]
        let candidates = app.scrollViews.buttons.allElementsBoundByIndex
            + app.collectionViews.cells.allElementsBoundByIndex
            + app.tables.cells.allElementsBoundByIndex

        for element in candidates {
            guard element.exists, element.isHittable else { continue }
            guard !tabTitles.contains(element.label) else { continue }
            // Полоса вкладок лежит у нижнего края — строку списка ищем выше неё.
            guard element.frame.midY < app.frame.height - 120 else { continue }
            element.tap()
            settle()
            return
        }
    }

    /// Нажимает кнопку по названию, если она на экране. Названия у кнопок панели
    /// заданы через `accessibilityLabel` — искать по ним надёжнее, чем по значку.
    @discardableResult
    private func tapButton(_ title: String, timeout: TimeInterval = 8) -> Bool {
        let button = app.buttons[title].firstMatch
        guard button.waitForExistence(timeout: timeout), button.isHittable else { return false }
        button.tap()
        settle()
        return true
    }

    /// Меню «…» в панели переписки. У кнопки нет подписи, поэтому берём её по значку.
    private func openChatMenu() -> Bool {
        let menu = app.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'ellipsis' OR label CONTAINS[c] 'Ещё'")
        ).firstMatch
        guard menu.waitForExistence(timeout: 8), menu.isHittable else { return false }
        menu.tap()
        settle()
        return true
    }

    /// Закрывает всплывающий экран — везде в приложении это «Закрыть».
    private func closeSheet() {
        for title in ["Закрыть", "Готово", "Отмена"] where app.buttons[title].firstMatch.exists {
            app.buttons[title].firstMatch.tap()
            settle()
            return
        }
        app.swipeDown()
        settle()
    }

    private func goBack() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists, back.isHittable {
            back.tap()
        } else {
            // Свой заголовок без системной панели — возвращаемся свайпом от края.
            app.swipeRight()
        }
        settle()
    }

    // MARK: - Кадры

    /// Снимок целиком, вместе со строкой состояния: в презентации нужен весь экран.
    private func snap(_ name: String) {
        settle()
        dismissSystemAlerts()
        shotIndex += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%02d-%@", shotIndex, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Пауза на дозагрузку данных и на затухание анимаций — иначе в кадр
    /// попадают полупрозрачные переходы и скелетоны вместо содержимого.
    private func settle() {
        _ = app.wait(for: .runningForeground, timeout: 5)
        Thread.sleep(forTimeInterval: 2.5)
    }

    /// Разрешения приложения — как их дал бы сотрудник при первом запуске.
    ///
    /// Монитор прерываний (`watchSystemAlerts`) срабатывает только на следующем
    /// касании приложения, а нам диалог мешает раньше — перед кадром. Поэтому
    /// закрываем его напрямую, обращаясь к оболочке.
    private func dismissSystemAlerts(waiting timeout: TimeInterval = 0) {
        let titles = ["Разрешить", "Allow", "Разрешить один раз", "Allow Once",
                      "При использовании приложения", "Allow While Using App",
                      "ОК", "OK", "Продолжить", "Continue"]

        if timeout > 0 {
            _ = springboard.alerts.firstMatch.waitForExistence(timeout: timeout)
        }

        // Диалогов может прилететь несколько подряд — снимаем, пока они есть.
        for _ in 0..<4 {
            let alert = springboard.alerts.firstMatch.exists
                ? springboard.alerts.firstMatch
                : app.alerts.firstMatch
            guard alert.exists else { return }

            guard let button = titles.map({ alert.buttons[$0] }).first(where: { $0.exists }) else { return }
            button.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// Страховка на случай, если диалог всплывёт посреди перехода: система
    /// покажет его тесту при следующем касании приложения.
    private func watchSystemAlerts() {
        addUIInterruptionMonitor(withDescription: "Системные разрешения") { alert in
            let titles = ["Разрешить", "Allow", "При использовании", "While Using App",
                          "OK", "Ок", "Продолжить", "Continue"]
            for title in titles {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }
}
