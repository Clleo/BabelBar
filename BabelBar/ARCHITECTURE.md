# BabelBar — Техническая документация

Документ для разработчика или AI-агента, который заходит в папку проекта и должен быстро понять: что это, как устроено, на каком этапе находится и где что менять.

> **Имена.** Отображаемое имя приложения — **BabelBar**. Bundle ID — `com.babelbar.app`.
> Внутреннее имя Xcode-проекта, таргета и схемы остаётся `BabelBar`.
> Переименование сломало бы подпись и пути сборки. Поэтому в коде и командах фигурирует `BabelBar`.

---

## 1. Что это за проект

**BabelBar** — нативное macOS-приложение для быстрого перевода RU ⇄ EN из строки меню (menu bar).

- Тип: menu-bar agent (без иконки в Dock, `LSUIElement = true`).
- UI: SwiftUI, тёмная glassmorphism-тема, синий акцент.
- Окно: выпадает из строки меню как `NSPopover`, можно открепить в плавающее окно.
- Перевод: через OpenAI-совместимый API (`/chat/completions`) — поддерживает OpenAI, DeepSeek и любой совместимый endpoint.
- Доп. функции: глобальные хоткеи, перевод выделенного текста, OCR-перевод области экрана (Vision).

Минимальная версия macOS — 13.0. Язык — Swift 5, SwiftUI + AppKit.

---

## 2. Как собрать и запустить

Сборка возможна **только на macOS с установленным Xcode** (это требование Apple — нативные macOS-приложения нельзя собрать на Linux).

**Вариант А — в один клик:**
1. Дважды кликнуть `build.command` в Finder.
2. Скрипт вызовет `xcodebuild`, соберёт Release без подписи, положит `BabelBar.app` на Рабочий стол и снимет карантин.

**Вариант Б — через Xcode:**
1. Открыть `BabelBar.xcodeproj`.
2. Схема `BabelBar` → Run (⌘R).

После запуска иконки в Dock нет — приложение живёт значком в строке меню (вверху справа).

---

## 3. Структура папки

```
BabelBar/                         ← корень проекта
├── BabelBar.xcodeproj/           ← проект Xcode (project.pbxproj — описание таргета и файлов)
├── build.command                     ← скрипт сборки в один клик
├── README.md                         ← краткая инструкция для пользователя
├── ARCHITECTURE.md                   ← ЭТОТ файл — техдокументация
└── BabelBar/                     ← исходники
    ├── BabelBarApp.swift         ← точка входа (@main)
    ├── AppDelegate.swift             ← статус-бар, popover, окно, контекстное меню
    ├── AppState.swift                ← главное состояние приложения (ObservableObject)
    ├── SettingsStore.swift           ← модели настроек + сохранение в UserDefaults
    ├── Keychain.swift                ← хранение API-ключа в Keychain
    ├── TranslationService.swift      ← клиент перевода (OpenAI-совместимый)
    ├── Clipboard.swift               ← работа с буфером, синтетический ⌘C
    ├── ScreenCapture.swift           ← скриншот области + Vision OCR
    ├── Transcriber.swift             ← Voice recognition (Whisper: local/remote, модели, валидация)
    ├── HotKeyManager.swift           ← глобальные хоткеи (Carbon + NSEvent monitor)
    ├── Info.plist                    ← LSUIElement, usage descriptions
    ├── BabelBar.entitlements     ← права (sandbox выключен, network client)
    ├── Assets.xcassets/              ← иконка приложения + AccentColor
    └── Views/
        ├── Theme.swift               ← палитра, glass-панель, IconButton
        ├── RootView.swift            ← переключает экраны translator / settings
        ├── TranslatorView.swift      ← главный экран переводчика
        └── SettingsView.swift        ← экран настроек
```

---

## 4. Архитектура и поток данных

Приложение построено вокруг одного объекта состояния `AppState` (паттерн ObservableObject).

```
              ┌──────────────────────────────────────────────┐
              │                  AppState                     │
              │  (inputText, outputText, screen, settings,    │
              │   sourceLang, targetLang, apiStatus, ...)     │
              └───────▲───────────────────────▲───────────────┘
                      │ @EnvironmentObject     │ callbacks (onRequestShow/Close/PinChanged)
        ┌─────────────┴──────────┐    ┌────────┴───────────┐
        │   SwiftUI Views        │    │   AppDelegate      │
        │ RootView →             │    │ NSStatusItem       │
        │  TranslatorView /      │    │ NSPopover / Window │
        │  SettingsView          │    │ контекстное меню   │
        └────────────────────────┘    └────────┬───────────┘
                                                │ configure(appState:)
                                       ┌────────┴───────────┐
                                       │  HotKeyManager     │
                                       │ ⌥Space / ⌘CC / ⇧⌘2 │
                                       └────────────────────┘

   AppState вызывает сервисы:
     • TranslationService.translate()   → перевод текста через API
     • ScreenCapture.captureAndRecognize() → OCR области экрана
     • ClipboardHelper                  → копирование/вставка/синтетический ⌘C
     • Keychain / SettingsStore         → хранение ключа и настроек
```

**Ключевой принцип:** UI и AppDelegate ничего не знают друг о друге напрямую — они общаются через `AppState` и его callbacks (`onRequestShow`, `onRequestClose`, `onPinChanged`).

---

## 5. Назначение каждого файла

### BabelBarApp.swift
Точка входа `@main`. Сцена `Settings { EmptyView() }` (стандартного окна нет — всё в popover). Подключает `AppDelegate` через `@NSApplicationDelegateAdaptor`.

### AppDelegate.swift
Сердце AppKit-интеграции:
- `setupStatusItem()` — создаёт `NSStatusItem` со значком; левый клик → popover, правый клик → контекстное меню (`showStatusMenu`: «Показать», «Настройки…», «Выйти»).
- `setupPopover()` — `NSPopover` (behavior `.transient`) с `NSHostingController(RootView)`.
- `detachableWindow(for:)` — при перетаскивании popover превращается в `NSWindow`; здесь скрываются кнопки-«светофор» (`standardWindowButton(...).isHidden = true`), размер 600×412.
- `popoverShouldDetach` → `true` (стрелка-«пимпочка» прячется при откреплении автоматически).
- `applyPinned()` — pin = уровень окна `.floating` (поверх всех).

### AppState.swift
`ObservableObject` со всем состоянием. Важное:
- `screen` — `.translator` / `.settings` (переключение экранов внутри того же окна).
- `inputText` / `outputText`, `sourceLang` / `targetLang`.
- `translate()` — запускает `TranslationService` в `Task`, результат пишет в `outputText` через `MainActor.run`.
- `resolveSource(for:)` — авто-определение языка (эвристика: считает кириллицу vs латиницу).
- `apiStatus` (вычисляемое) — три состояния индикатора:
  - `.offline` (серый) — нет API-ключа;
  - `.exhausted` (красный) — `tokensUsed ≥ tokensLimit`;
  - `.online` (зелёный) — всё готово.
- `handleTranslateSelection()` — копирует выделение (синтетический ⌘C) → переводит.
- `handleScreenshotTranslate()` — OCR области экрана → перевод.
- Callbacks `onRequestShow/Close/PinChanged` связываются в `AppDelegate`.

> Примечание: класс намеренно **без** `@MainActor` — иначе возникает конфликт изоляции при обращении из `AppDelegate`. Обновления UI идут через `MainActor.run`.

### SettingsStore.swift
- `enum APIProvider` (openai / deepseek / custom) с дефолтными `baseURL` и `model`.
- `enum Appearance` (light / dark / system).
- `struct AppSettings: Codable` — все настройки **кроме** секретов (`apiKey`, `apiKey2`, `transcriptionAPIKey` намеренно не входят в `CodingKeys`). Кастомный `init(from:)` устойчив к отсутствующим полям.
- `SettingsStore.load()/save()` — JSON в `UserDefaults` под ключом `babelbar.settings`; секреты читаются/пишутся через `Keychain`, в JSON не попадают.
- Миграция: старые ключи (`translatebar.*`) игнорируются.

### Keychain.swift
Обёртка над Security framework. `set(_:for:)` / `get(_:)` — секреты хранятся как generic password в service `com.babelbar.secrets`, аккаунты: `apiKey`, `apiKey2`, `transcriptionAPIKey`, `license`.

### TranslationService.swift
`translate(text:from:to:settings:)` — собирает запрос к `{baseURL}/chat/completions`:
- system-промпт: «переведи с X на Y, верни только перевод» + пользовательские AI Instructions;
- модель из настроек, `temperature 0.2`;
- авторизация `Bearer {apiKey}`;
- разбирает `choices[0].message.content`.
Ошибки — через `TranslationError` (missingKey / badResponse / noContent).

### Clipboard.swift
- `copy()` / `read()` — буфер обмена.
- `copySelectionAndRead()` — постит синтетический ⌘C (`CGEvent`, virtualKey 0x08 + maskCommand), ждёт изменения `changeCount` и читает выделение. **Требует разрешение Accessibility.**

### ScreenCapture.swift
- `captureAndRecognize()` — запускает `/usr/sbin/screencapture -i` (интерактивный выбор области) во временный PNG, затем Vision OCR.
- `recognizeText(in:)` — `VNRecognizeTextRequest`, языки `ru-RU` + `en-US`, accurate. **Требует разрешение Screen Recording.**

### HotKeyManager.swift
Глобальные хоткеи:
- `⌥ + Space` и `⇧ + ⌘ + 2` — через Carbon `RegisterEventHotKey` + `InstallEventHandler`.
- `⌘ + C + C` (двойной ⌘C) — через `NSEvent.addGlobalMonitorForEvents`, считает два нажатия в пределах 0.5 c.

### Transcriber.swift
Голосовое распознавание (Voice-to-Text). Содержит:
- `protocol Transcriber` — интерфейс для разных реализаций.
- `LocalWhisperTranscriber` — использует **WhisperKit** (on-device, CoreML, быстро, приватно). Автоматически скачивает и кэширует Whisper модели в `~/.cache/whisper/` при первом использовании.
- `RemoteWhisperTranscriber` — отправляет аудио на **Groq Whisper API** (требует ключ, но облако).
- `WhisperModelManager` — управляет кэшем моделей. **Недавнее улучшение (v1.0.8)**: правильная валидация папок (отличает полные корректные загрузки от промежуточных кэш-папок, автоисцеляется при миграции).
- `AudioRecorder` — захват аудио с микрофона (буферизация, нормализация громкости).
- Audio ducking: система автоматически понижает громкость во время диктовки.

**Дефолт**: LocalWhisperKit (первый запуск → скачивание модели, ~600 MB). Хоткей: **Fn** = диктовка + вставка, **Shift+Fn** = диктовка + перевод.

### Views/Theme.swift
Палитра (`bgTop/bgBottom` — тёмный navy-charcoal, `accentBlue/Purple/Green`), модификатор `glassPanel(corner:)` (полупрозрачная панель + тонкий бордер), `IconButton`.

### Views/RootView.swift
Фон (градиент + синее свечение в углу) + `switch state.screen` между `TranslatorView` и `SettingsView`. `preferredColorScheme` зависит от `settings.appearance`.

### Views/TranslatorView.swift
Главный экран: верхняя панель (заголовок, переключатель RU⇄EN, Clear, pin, settings, close), два текстовых блока со счётчиками и copy, нижняя панель (бейдж ⌘+C+C, индикатор `apiStatus`). Скрытая кнопка `⌘↵` запускает перевод.

### Views/SettingsView.swift
Экран настроек (компактный, шрифт 12). Две секции: APP SETTINGS (Appearance, хоткеи, языки) и API SETTINGS (Provider, Base URL, Model, API Key, прогресс токенов, AI Instructions). Кнопка **Save Changes** пишет ключ в Keychain и вызывает `state.saveSettings()`.

---

## 6. Текущий статус проекта

**Готово и работает (проверено):**
- Сборка проходит, приложение запускается menu-bar агентом.
- UI переводчика и настроек; тёмная glassmorphism-тема, скругление 16 во всех элементах.
- Своя иконка приложения (squircle A↔Я, 10 размеров 16–1024).
- Открепление popover в плавающее окно: своё borderless-окно с `NSVisualEffectView`
  (`.menu` материал, тёмный appearance, скруглённые углы через `maskImage`, белая рамка 1pt).
  Закрытие открепленного окна **не убивает** статус-иконку (`orderOut` вместо `close`).
- Перевод через API (OpenAI / DeepSeek / custom). **Авто-перевод** при вставке текста
  и по Enter; запасной хоткей ⌘+Return.
- **Реальный счётчик токенов**: после каждого запроса прибавляется `usage.total_tokens`.
  Одноразовая миграция убрала старое демо-значение 124 500.
- Текстовые поля — свой `PlainTextView` (NSTextView): без скроллбаров, белый текст в тёмной теме.
- Hover-эффекты на всех кнопках.
- Глобальные хоткеи: ⌥Space, ⇧⌘2, и ⌘+C+C — **независимо от раскладки** (матч по keyCode).
- API-ключи (перевод + транскрипция) хранятся в **Keychain** (service `com.babelbar.secrets`); остальные настройки — в `UserDefaults`.
- **Voice Recognition** (Whisper) — локальное (WhisperKit, первый запуск ~600 MB) или удалённое (Groq API).
  Автоматическая загрузка моделей с правильной валидацией (отличает полные загрузки от промежуточного кэша).
- **Стабильная подпись** сертификатом Apple Development → выданные разрешения
  (Мониторинг ввода) не слетают при пересборках.

**Требует разрешений macOS (один раз):**
- **Мониторинг ввода** (Input Monitoring) — для глобального ⌘+C+C.
- **Screen Recording** — для OCR-перевода области экрана (⇧⌘2).
- System Settings → Конфиденциальность и безопасность.
- Без введённого API-ключа перевод вернёт «API key is missing» (индикатор серый).

**Известные ограничения / потенциальные доработки:**
- Хоткеи в настройках — статичные бейджи (не переназначаются из UI).
- Индикатор API не пингует endpoint (смотрит только наличие ключа и лимит токенов).
- Лимит токенов (`tokensLimit`) задаётся по умолчанию (500 000); провайдеры не отдают «лимит в токенах» по API.

---

## 7. Как типично вносить изменения

- **Поменять цвета/тему** → `Views/Theme.swift` (+ `Assets.xcassets/AccentColor` для нативных контролов).
- **Добавить провайдера API** → `enum APIProvider` в `SettingsStore.swift` (добавить case + `defaultBaseURL`/`defaultModel`).
- **Поменять логику перевода/промпт** → `TranslationService.swift`.
- **Добавить пункт в меню статус-бара** → `showStatusMenu()` в `AppDelegate.swift`.
- **Изменить хоткеи** → `HotKeyManager.swift`.
- **Сделать счётчик токенов реальным** → в `TranslationService.translate()` вернуть `usage`, в `AppState.translate()` прибавить к `settings.tokensUsed` и сохранить.
- **Изменить размер окна** → `contentSize` в `setupPopover()` и `setContentSize` в `detachableWindow()` (`AppDelegate.swift`) + `frame(minWidth/minHeight)` в `RootView.swift`.

---

## 8. Полезное для отладки

- Запуск с выводом в терминал: `./BabelBar.app/Contents/MacOS/BabelBar`.
- Логи/краши: **Console.app** → Crash Reports → `BabelBar`.
- Приложение не видно после запуска — это нормально: ищи значок в **строке меню**, не в Dock.
- Если перевод не работает — проверь индикатор: серый = нет ключа, красный = нет токенов, зелёный = должно работать (тогда смотри `errorMessage` под полем ввода).

---

## 9. Актуальное состояние (для продолжения в новой сессии)

**Версия**: 1.0.8 (build 5). Отображаемое имя — **BabelBar** (bundle ID `com.babelbar.app`).
Подпись — **Apple Development** (стабильно, разрешения не слетают):
`codesign --force --deep --options runtime --entitlements BabelBar/BabelBar.entitlements
--sign 9A9B8DDE5265383479D320E3A0DC5037DC3792C9 <app>`.

**Оболочка** (`AppDelegate.swift`): NSPopover убран — **одно borderless-окно** (`KeyableBorderlessWindow`)
с `BlurContainerViewController` (NSVisualEffectView, скругление 16 через maskImage), авто-высота через
`sizingOptions`. **Настройки — отдельное окно** (перетаскиваемое). Пока открыто любое окно — policy
`.regular` (иконка в Dock + Cmd-Tab), иначе `.accessory`. Окна открываются на **текущем экране**
(`moveToActiveSpace`). Open-хоткей **toggle**, **Escape** скрывает.

**Перевод** (`AppState.swift`, `TranslationService.swift`): авто-определение направления RU⇄EN;
оба поля редактируемые (нижнее → обратный перевод по Enter); **два провайдера** с авто-fallback;
реальный счётчик токенов. Провайдеры: OpenAI/DeepSeek/z.ai/Claude/Groq/Custom.

**Голос** (Transcriber.swift): локальная (WhisperKit) или удалённая (Groq API) транскрипция.
Хоткеи: **Fn** (диктовка), **Shift+Fn** (диктовка + перевод). Автоматическое управление моделями.
v1.0.8: улучшена валидация Whisper моделей (корректно отличает полные загрузки от кэш-папок).

**Тема — модуль ThemeKit** (`ThemeKit.swift` + `InlineColorPicker.swift`): отдельные палитры
dark/light (Accent/Background/Surface/Foreground + Contrast/BackgroundOpacity/Blur per-theme),
размер текста; свой color-picker во `.popover`; живое перекрашивание через `themeRevision`
(Environment) + статический `Theme`; оформление окна/материал блюра следуют теме.

**Голос** (`SpeechDictation.swift`, `VoiceInput.swift`, `RecordingOverlay.swift`, `SystemAccess.swift`):
- В поле ввода — кнопка микрофона (диктовка → авто-перевод).
- Глобально через **CGEventTap** (как FreeFlow): ловит Fn (keyCode 63), может «съесть» нажатие.
  Настраиваемые модификатор-комбо (`ModifierCombo`, дефолт **Fn** и **Shift+Fn**), режим
  **hold-or-tap**. **Fn** → диктовка под курсор (CGEvent unicode-печать). **Shift+Fn** → диктовка →
  фоновый перевод → печать перевода **под курсором** (не открывает окно; не путать с ⌘C+C).
  Язык распознавания всегда авто-детект. Подробности — `SPEC.md` §7.1.
- При остановке — пауза 0.7с (`finishAudio()` → `cancel()`), чтобы не обрезать концовку.
- **RecordingOverlay** — «пилюля» у нотча: панель продлевается вверх до края экрана, заполняет нотч
  чёрным → сливается с ним (ширина точно по нотчу через `auxiliaryTop*Area`), снизу выступает ~22px
  с анимированной волной в акцентных цветах. Триггер-звук (системный, громкость/выбор в настройках).

**Разрешения нужны:** Универсальный доступ (event-tap, синтетический ⌘V/печать), Мониторинг ввода
(⌘C+C), Микрофон + Распознавание речи (диктовка), Запись экрана (OCR). Секция Permissions в настройках.

**Лицензия/монетизация:** UI-заглушка триала в настройках (секция LICENSE). Решили модель
**бесплатно + добровольная поддержка** (`MONETIZATION.md`); DRM не нужен. Лендинг — `LANDING_BRIEF.md`
(Next.js/Vercel, classic CSS, дружеский тон, домен `babelbar.app`).

**Новые файлы:** `KeyCombo.swift`, `ThemeKit.swift`, `InlineColorPicker.swift`, `SystemAccess.swift`,
`SpeechDictation.swift`, `VoiceInput.swift`, `RecordingOverlay.swift`. Все добавлены в
`project.pbxproj` (ручные id `...0020`–`...0026`).
