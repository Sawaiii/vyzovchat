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

    /// Снимаем ли вымышленные данные вместо рабочих — попадает в отчёт,
    /// чтобы это было видно, не разглядывая кадры.
    private var usingDemoData = false

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
            // Календарь показывает лишь плотность дней — содержательнее список
            // отчётов по компаниям и сводка отработанных смен.
            if tapButton("Все отчёты") { snap("dashboard-reports") }
            if tapButton("Смены") { snap("dashboard-shifts") }
        }

        // Диск.
        tapTab("Диск")
        snap("disk")

        // Профиль.
        tapTab("Профиль")
        snap("profile")

        print(usingDemoData
              ? "ИТОГ: кадры сняты на вымышленных данных"
              : "ИТОГ: кадры сняты на рабочем сервере")
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

        // По умолчанию снимаем вымышленные данные: на рабочем сервере чатов
        // мероприятий нет, да и рабочие переписки в презентации ни к чему.
        // Съёмку с сервера можно вернуть переменной SHOTS_DEMO=0.
        if secret("SHOTS_DEMO") != "0" {
            restartWithDemoData(reason: "выбран показ вымышленных данных")
            return
        }

        guard let user = secret("DEMO_LOGIN"), let pass = secret("DEMO_PASSWORD") else {
            XCTFail("Нет DEMO_LOGIN/DEMO_PASSWORD: без учётной записи внутрь приложения не попасть")
            return
        }

        type(user, into: login)
        typePassword(pass)

        let submit = app.buttons["Войти"].firstMatch
        guard submit.isEnabled else {
            restartWithDemoData(reason: "поле пароля не приняло ввод")
            return
        }
        submit.tap()

        // Вошли — это видно по полосе вкладок. Если её нет, дальше снимать нечего:
        // пусть прогон покраснеет здесь, а не отдаст десяток одинаковых кадров.
        guard named("Чаты").waitForExistence(timeout: 60) else {
            // Сервер мог ответить отказом — тогда причина написана прямо на экране.
            let banner = app.staticTexts.allElementsBoundByIndex
                .map(\.label)
                .first { $0.contains("парол") || $0.contains("сотрудник") || $0.contains("связи") }
            restartWithDemoData(reason: "сервер не пустил, экран сообщает: \(banner ?? "ничего")")
            return
        }
    }

    /// Заполняет поле.
    private func type(_ text: String, into field: XCUIElement) {
        field.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeText(text)
    }

    /// Пароль набираем в открытом виде.
    ///
    /// Защищённое поле в симуляторе ввод нередко теряет: фокус ставится, а текст
    /// не доходит. У поля есть кнопка показа пароля — нажимаем её, набираем в
    /// обычное поле и прячем обратно. Кадр экрана входа снят раньше, так что
    /// пароль в открытом виде никуда не попадает.
    private func typePassword(_ pass: String) {
        let eye = app.buttons["eye"].firstMatch
        if eye.waitForExistence(timeout: 5), eye.isHittable {
            eye.tap()
            let open = app.textFields["Пароль"]
            if open.waitForExistence(timeout: 5) {
                type(pass, into: open)
                let hide = app.buttons["eye.slash"].firstMatch
                if hide.exists, hide.isHittable { hide.tap() }
                return
            }
        }

        // Запасной путь — как обычно, в защищённое поле.
        let secure = app.secureTextFields["Пароль"]
        if secure.waitForExistence(timeout: 5) {
            type(pass, into: secure)
        }
    }

    /// Запускает приложение заново на вымышленных данных.
    ///
    /// Нужен, когда попасть на рабочий сервер не удалось: презентации нужны
    /// заполненные экраны, а не пустой список. Данные вымышленные — рабочие
    /// переписки в презентацию и не попадут.
    private func restartWithDemoData(reason: String) {
        usingDemoData = true
        // Кадры, снятые до сюда, относятся к рабочей сборке — нумерацию
        // продолжаем, чтобы порядок в презентации не сбился.
        app.terminate()
        app.launchArguments.append("-demoData")
        app.launch()
        dismissSystemAlerts(waiting: 10)

        XCTAssertTrue(named("Чаты").waitForExistence(timeout: 60),
                      "Не открылся список чатов даже на вымышленных данных (\(reason))")
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
        return named(label).waitForExistence(timeout: timeout)
    }

    /// Элемент по подписи, любого типа.
    ///
    /// Полоса вкладок нарисована своими кнопками со стилем `.plain`, и в дереве
    /// доступности «Чаты» приходит надписью, а не кнопкой. Поэтому ищем по
    /// подписи среди всего, а не в конкретной коллекции.
    private func named(_ label: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@", label)
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists { return button }
        let text = app.staticTexts.matching(predicate).firstMatch
        if text.exists { return text }
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Переключает вкладку. Возвращает `false`, если такой вкладки нет —
    /// у рядового сотрудника, например, нет «Отчётов».
    @discardableResult
    private func tapTab(_ title: String) -> Bool {
        dismissSheetIfNeeded()
        let tab = named(title)
        guard tab.waitForExistence(timeout: 10) else { return false }
        // По надписи внутри кнопки система не даёт нажать напрямую — жмём в её точку.
        if tab.isHittable { tab.tap() } else { tab.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap() }
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
            // Кнопки-значки (плюс, поиск, фильтр) подписи почти не имеют —
            // строка списка всегда несёт название мероприятия.
            guard element.label.count > 8 else { continue }
            // Ниже панели сверху и выше полосы вкладок снизу.
            guard element.frame.minY > 140,
                  element.frame.midY < app.frame.height - 120 else { continue }
            element.tap()
            settle()
            return
        }
    }

    /// Закрывает всплывший экран, если он открыт: иначе следующий кадр снимет
    /// не тот экран, который нужен.
    private func dismissSheetIfNeeded() {
        for title in ["Отмена", "Закрыть", "Готово"] {
            let button = app.navigationBars.buttons[title].firstMatch
            if button.exists, button.isHittable {
                button.tap()
                settle()
                return
            }
        }
    }

    /// Нажимает кнопку по названию, если она на экране. Названия у кнопок панели
    /// заданы через `accessibilityLabel` — искать по ним надёжнее, чем по значку.
    @discardableResult
    private func tapButton(_ title: String, timeout: TimeInterval = 8) -> Bool {
        let button = named(title)
        guard button.waitForExistence(timeout: timeout) else { return false }
        if button.isHittable { button.tap() } else { button.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap() }
        settle()
        return true
    }

    /// Меню «…» в панели переписки. У кнопки нет подписи, поэтому берём её по значку.
    private func openChatMenu() -> Bool {
        let bar = app.navigationBars.firstMatch
        guard bar.waitForExistence(timeout: 8) else { return false }

        // Подписи у кнопки нет, зато она крайняя справа — берём последнюю в панели.
        let buttons = bar.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        guard let menu = buttons.last else { return false }
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
