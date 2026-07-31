# Vyzov Chat — iOS

Нативное iOS-приложение (SwiftUI) — клиент чата мероприятий для выездных бригад.
Работает с тем же бэкендом, что и веб-версия: **https://vyzovchat.ru**.

Приложение — самостоятельный клиент: оно только читает и пишет данные через
публичный API сервера. Код сервера и веб-версии живёт в отдельном репозитории и
этим проектом не меняется.

## Как устроено соединение с сервером

| Что | Как |
|---|---|
| Авторизация | `POST /api/login {login, pass}` → `{worker, token}`; дальше `Authorization: Bearer <token>` |
| Реалтайм | WebSocket `/ws?token=<token>`, обмен JSON-кадрами (не Socket.IO) |
| Отправка сообщений | только через WebSocket (`send` / `dm`), REST-эндпоинта нет |
| Медиа | `POST /api/uploads/presign` → PUT напрямую в S3 → ключ уходит в WebSocket-кадре |
| Показ медиа | сервер отдаёт готовые подписанные ссылки `media_url` / `thumb_url` / `download_url` |

Токен хранится в Keychain (`Networking/TokenStore.swift`), базовый адрес — в
`Networking/AppConfig.swift`.

## Структура

```
VyzovChat/
├── project.yml                  # конфиг XcodeGen (генерирует .xcodeproj)
├── VyzovChat/
│   ├── App/                     # точка входа, сессия, корневой роутер
│   ├── Networking/              # APIClient, DTO, конфиг, хранилище токена
│   ├── Services/                # протоколы + реальные реализации (Real*.swift)
│   ├── Models/                  # доменные модели: User, Deal, Chat, Message
│   ├── Features/                # экраны: Auth, Chats, Chat, Deals, Disk, Photobank, Profile…
│   ├── DesignSystem/            # тема, типографика, стекло, контролы, хаптика
│   ├── Components/              # общие вьюхи
│   └── Resources/               # Info.plist, Assets.xcassets
```

## Сборка

Нативный Swift компилируется **только на macOS**. Своего Mac для работы не нужно —
сборку делает бесплатный GitHub Actions, установка идёт с Windows.

**Шаг 1 — собрать `.ipa` в облаке.** Пуш в `main` (или вручную: вкладка
**Actions → Build unsigned IPA → Run workflow**) запускает сборку неподписанного
`.ipa` на раннере `macos-15`. Готовый файл: Actions → нужный запуск →
**Artifacts → `VyzovChat-unsigned-ipa`**.

> Раннер именно `macos-15`: `macos-14` не читает формат проекта, который генерирует
> свежий XcodeGen. Проект `.xcodeproj` в репозиторий не коммитится — он собирается
> из `project.yml`.

**Шаг 2 — поставить на iPhone с Windows.**
1. Установите **Sideloadly** (или AltStore/AltServer) и **iTunes + iCloud с сайта
   Apple** — не версии из Microsoft Store, нужны их драйверы.
2. Подключите iPhone кабелем, войдите бесплатным **Apple ID**.
3. Перетащите скачанный `.ipa` в Sideloadly → Start — он подпишет и установит.
4. На iPhone: *Настройки → Основные → VPN и управление устройством* → доверить Apple ID.

**Ограничения бесплатной подписи:** приложение живёт 7 дней (потом переподписать),
до 3 приложений на Apple ID, только для личного теста. Для раздачи команде нужен
Apple Developer Program ($99/год) и TestFlight — он же нужен для push-уведомлений.

## Сборка на Mac (если он есть)

```bash
brew install xcodegen
xcodegen generate
open VyzovChat.xcodeproj
```

Для установки на устройство впишите свой Team ID в `project.yml`
(`DEVELOPMENT_TEAM`) либо выберите команду вручную после генерации.
