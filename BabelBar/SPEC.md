# BabelBar — Reference Spec

Единый источник правды по размерам, поведению и функционалу. Код сверяется с этим документом.

## 1. Тип приложения
- macOS menu-bar agent (`LSUIElement`), без иконки в Dock.
- SwiftUI + AppKit, минимум macOS 13.
- Подпись: Apple Development cert (стабильный designated requirement → разрешения не слетают).

## 2. Окно (оболочка)
- **Одно** кастомное borderless-окно (`KeyableBorderlessWindow`) — и прикреплённое, и плавающее.
  NSPopover не используется (нет чужеродной стрелки, нет мигания при «откреплении»).
- Ширина: **600**. Высота: **translator 388**, **settings 580**. Высота меняется автоматически
  через `NSHostingController.sizingOptions = [.preferredContentSize]` + per-screen высота в RootView.
- Фон: `NSVisualEffectView` (material `.menu`, appearance `.darkAqua` для тёмной темы),
  скругление **16** через `maskImage`, тонкая рамка `white 0.10`.
- Показ: под кнопкой статус-бара, `makeKeyAndOrderFront`.
- Транзиентность: глобальный мониторинг клика вне приложения → скрыть (если не запинено).
  Клик по иконке статус-бара — toggle. Дочерний color-popover окно не закрывает.
- Пин: уровень `.floating`. Крест/Save: `orderOut`. Перетаскивание: по фону.

## 3. Экран переводчика (TranslatorView)
- Топ-бар: `Заголовок «BabelBar» (12, semibold, secondary)` → переключатель языков ВПЛОТНУЮ
  к заголовку → Spacer → `Clear` → pin → gear → ✕. Иконки 12pt в 22×22, hover-подсветка.
- Две текстовые области: minHeight **140**, скругление 16, шрифт = `Theme.translationFontSize`
  (дефолт 14). Без скроллбаров (`PlainTextView`/NSTextView). Цвет текста = `Theme.textPrimary`.
- Боттом-бар: бейдж `⌘+C+C` (10pt), «for quick copy», по центру — «Вставить перевод »»»
  (regular), справа — индикатор API (точка + label, 10pt).
- Перевод: авто при вставке (изменение >1 символа) и по Enter; запасной ⌘↵.

## 4. Направление перевода (авто)
- При переводе язык исходника определяется по тексту (кириллица → RU, иначе EN).
- `targetLang` = противоположный исходнику (в паре RU/EN). Оба публикуются — индикатор
  всегда корректен и не залипает (никогда не X⇄X).
- `swapDirection()` меняет местами реальные стороны + текст; не создаёт X⇄X.
- Выделение (⌘C+C) и скриншот-OCR используют ту же авто-логику.

## 5. Настройки (SettingsView), сверху вниз
1. Header: «BabelBar Settings» + индикатор API + ✕.
2. **APP SETTINGS**: Appearance (Light/Dark/System), хоткеи (рекордеры), Language Preferences.
3. **API SETTINGS**: Provider, Base URL, Model, API Key, Tokens Used (реальные), AI Instructions.
4. **THEME** — последней, рядом с Save.
5. **Save Changes** — сохраняет и возвращает на экран переводчика (закрывает настройки).
- Внутренние отступы секций 20, расстояние строк 16; ширина полей API 400; скругл'`glassPanel` 16.
- Прокрутка без полосы (`.scrollIndicators(.never)`).

## 6. Модуль темы (ThemeKit)
- Палитры **независимы**: `config.dark` и `config.light` (Accent / Background / Surface /
  Foreground), плюс общие `contrast` (0–100, 50 = нейтр.) и `translationTextSize` (px, поле ввода).
- Изоляция строгая: правка тёмной палитры НЕ влияет на светлую и наоборот.
- `Theme.apply` применяет цвета честно (panel = surface как есть; фон = background; текст =
  foreground; акцент = accent). Swatch = ровно выбранный hex. Контраст — отдельный регулятор,
  пивот вокруг 0.5.
- Color-picker — **свой** (`InlineColorPicker`): квадрат saturation/brightness + полоса hue +
  hex-поле, открывается в `.popover` рядом со swatch внутри окна. Живое применение.
- Дефолты: dark {accent #5C73F2, bg #16171D, surface #23252E, fg #FFFFFF};
  light {accent #3467AB, bg #EEF0F5, surface #FFFFFF, fg #1C1E27}; contrast 50; size 14.
- Применяется ко всему: фон окна, внутренние панели/поля (`glassPanel`), текст, акцент, размер.

## 7. Хоткеи (HotKeyManager) — настраиваемые
- Open (дефолт ⌥Space), Translate selection (двойное нажатие, дефолт ⌘C+C),
  Screenshot OCR (дефолт ⇧⌘2). Матч по физическому keyCode (раскладко-независимо).
- Запись комбинаций в настройках (`HotKeyRecorder`), применяется сразу.

## 7.1. Голосовые шорткаты (VoiceHotkeys) — модификатор-комбо
Глобальные комбо только из модификаторов (Fn / ⇧ / ⌃ / ⌥ / ⌘), ловятся через **CGEventTap**
на отдельном потоке (Fn = keyCode 63 нельзя поймать Carbon-хоткеем). Режим **hold-or-tap**:
зажал-говори-отпустил, либо тап-говори-тап. Звук-триггер при старте, оверлей-«пилюля» у нотча.
Две **независимые** функции:

1. **Диктовка под курсор** — дефолт **Fn**. Запись → Whisper → печать распознанного текста под
   курсором (`startCursorDictation` / `stopCursorDictation` → `TextInserter`). Перевода нет.
2. **Диктовка + перевод под курсор** — дефолт **⇧Fn** (`translateDictateHotkey`). Запись → Whisper →
   фоновый перевод (направление из Источник/Цель, `resolveDirection`) → печать перевода под
   курсором (`startCursorTranslateDictation` / `stopCursorTranslateDictation`). Оверлей держит
   лоадер, пока идёт перевод. Не связана с `Translate selection` (⌘C+C).

- **Язык распознавания — всегда авто-детект** (`dictationLanguage()` возвращает `nil`).
  Намеренно НЕ привязан к `settings.sourceLang`: тот задаёт направление перевода, а не язык речи.
  Проброс его в Whisper форсирует language-токен, и модель выдаёт этот язык для ЛЮБОЙ речи —
  то есть молча переводит (при дефолте Источник=RU английская диктовка давала русский текст).
- Матч комбо — по **точному** набору модификаторов, супер-комбо приоритетнее подмножества,
  иначе ⇧Fn стартовал бы обычную диктовку на промежуточном состоянии «нажат только Fn».
- Биндинги в `AppDelegate` (`VoiceHotkeys.shared.bindings`), `VoiceAction` =
  `.dictateToCursor` / `.dictateTranslateToCursor`. Пустое комбо = функция выключена.
- Рекордеры в настройках (`ModifierComboRecorder`), мастер-выключатель `voiceInputEnabled`.
- Если назначен **Fn** — в Системных настройках → Клавиатура поставить Fn на «Не выполнять действий».

## 8. Разрешения macOS (один раз)
- **Мониторинг ввода** — для глобального ⌘C+C.
- **Универсальный доступ** — для синтетического ⌘V (кнопка «Вставить перевод»), ⌘C и event-tap
  голосовых комбо (печать текста под курсором).
- **Микрофон + Распознавание речи** — для голосовых шорткатов (диктовка / диктовка+перевод).
- **Запись экрана** — для OCR (⇧⌘2).

## 9. Хранение
- Настройки — в `UserDefaults` (JSON). **API-ключи — в Keychain** (`apiKey`, `apiKey2`,
  `transcriptionAPIKey` намеренно не входят в `CodingKeys`, см. `SettingsStore`).
- Тема — отдельный ключ `translatebar.theme`.

## 10. Сборка
- `build.command`: xcodebuild Release → копия на Desktop → `xattr -cr` → подпись Apple
  Development identity (fallback ad-hoc) с entitlements.
