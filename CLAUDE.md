# BabelBar — руководство по репозиторию

macOS-приложение в строке меню. Xcode-проект: `BabelBar/BabelBar.xcodeproj`.
Обновления клиентам раздаются через **GitHub Releases** — приложение само опрашивает API.

---

## Выпуск новой версии — полный цикл

Фикс не считается доставленным, пока не опубликован релиз. Приложение узнаёт об
обновлении **только** из `https://api.github.com/repos/Clleo/BabelBar/releases/latest`.
Коммит в `main` пользователям ничего не даёт.

Шаги, все обязательны:

**1. Поднять версию — в двух местах сразу.**

- `VERSION` в корне репозитория (`app/VERSION`) — источник правды для `release.command`.
- `MARKETING_VERSION` и `CURRENT_PROJECT_VERSION` в `BabelBar/BabelBar.xcodeproj/project.pbxproj`.

`MARKETING_VERSION` = версия для пользователя (`CFBundleShortVersionString`, имя DMG,
надпись в настройках). `CURRENT_PROJECT_VERSION` = внутренний build number.
Если разойдутся — приложение покажет одну версию, а сравнивать с релизом будет другую.

**2. Собрать подписанный Release.**

```bash
cd app/BabelBar
xcodebuild -project BabelBar.xcodeproj -scheme BabelBar -configuration Release \
  -derivedDataPath .release_build build \
  DEVELOPMENT_TEAM=QYX3YDV75G CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates
```

Подпись **только** реальным сертификатом Apple Development, никогда не ad-hoc
(`CODE_SIGN_IDENTITY="-"`). macOS привязывает TCC-разрешения (Универсальный доступ,
Мониторинг ввода, Запись экрана, Микрофон) к подписи: ad-hoc даёт
`Identifier=BabelBar`, `TeamIdentifier=not set`, macOS считает это другим приложением
и молча перестаёт применять уже выданные разрешения. Так сломался билд 1.0.5.

Проверка:

```bash
codesign -dvvv .release_build/Build/Products/Release/BabelBar.app
```

Должно быть: `Identifier=com.babelbar.app`, `TeamIdentifier=QYX3YDV75G`,
`flags=0x10000(runtime)`, `Authority=Apple Development: clleoweb@gmail.com (TZ8TY6ZH56)`.
Другого валидного identity на машине нет.

**3. Собрать DMG.** Только через `BabelBar/dmg/dmg_build.sh` — он делает оформленное
окно установки (фирменный фон, приложение слева, `Applications` справа, стрелка
«drag and drop»), а не голый том. Готовые DMG лежат в корне `app/`.

```bash
cd app/BabelBar
./dmg/dmg_build.sh .release_build/Build/Products/Release/BabelBar.app ../BabelBar-<версия>.dmg BabelBar
```

Что внутри скрипта и где что править — см. `BabelBar/dmg/README.md`. Раскладку окна
пишет Finder, поэтому нужен доступ «Автоматизация → Finder»; без него DMG соберётся
без оформления (скрипт об этом предупредит — молча плохой образ не уедет).

Альтернатива для ручного запуска: `BabelBar/release.command <версия>` делает шаги 1–3
(но `CURRENT_PROJECT_VERSION` не трогает и релиз не публикует).

**4. Закоммитить и запушить в `main`.** Релизы в этом проекте идут прямо в `main` —
ветку заводить не нужно, так устроена вся история. `.dmg`-файлы не коммитим.

**5. Опубликовать GitHub Release — без этого шага апдейт не доедет.**

```bash
gh release create v<версия> ../BabelBar-<версия>.dmg \
  --title "BabelBar <версия>" \
  --notes "<что изменилось, на языке пользователя>"
```

Требования, которые проверяет апдейтер в `AppState.checkForUpdates()`:

- тег вида `v2.0.2` — приложение срезает ведущий `v`;
- релиз **не draft и не prerelease**, иначе `releases/latest` его не вернёт;
- среди assets есть файл с расширением `.dmg` — по нему работает установка прямо
  в приложении; без него кнопка лишь откроет страницу релиза.

**6. Проверить тот же эндпоинт, что дёргает приложение:**

```bash
curl -s https://api.github.com/repos/Clleo/BabelBar/releases/latest | grep -E '"tag_name"|browser_download_url'
```

---

## Как приложение узнаёт об обновлении

- `AppState.checkForUpdates()` — запрос к `releases/latest`, сравнение с текущей версией
  через `isVersion(_:newerThan:)`, поиск `.dmg` среди assets.
- Автопроверка при запуске (`checkForUpdatesOnLaunch`), не чаще раза в 6 часов,
  и ещё раз при открытии настроек.
- `AppState.updateAvailable` включает зелёную точку на шестерёнке в главном окне,
  точку у пункта «О приложении» в боковом меню настроек и баннер над карточками.
- `installUpdate()` качает DMG, монтирует, заменяет `.app` и перезапускает приложение.

Подпись при обновлении не меняется (`com.babelbar.app`, team `QYX3YDV75G`), поэтому
TCC-разрешения сохраняются.

---

## Ловушки, на которых уже обжигались

- **WhisperKit: `language: nil` — это не автоопределение.** При дефолтном
  `usePrefillPrompt: true` флаг `detectLanguage` равен `false`, и декодер подставляет
  `<|en|>`. Форсированный английский токен заставляет Whisper *переводить* русскую речь
  вместо транскрипции. Всегда передавать `detectLanguage: language == nil`.
- **Локальная модель не должна скачиваться внутри распознавания.** `ensureLoaded()`
  тянет сотни мегабайт молча, оверлей висит на лоадере, вид полного зависания.
  Загрузка — только через настройки (`WhisperModelManager`).
- **CGEventTap отключается системой.** По `tapDisabledByTimeout` нужно не только
  включить tap обратно, но и перечитать реальные `NSEvent.modifierFlags`: пока tap был
  выключен, отпускание Fn не пришло, и сессия диктовки зависала навсегда.
- **Высота окна настроек.** Никаких `ScrollView` и жадных `Spacer` в колонке контента —
  они сообщают наверх почти нулевую высоту, и окно схлопывается (см. комментарии
  в `SettingsView`).

---

## Структура

`www/BabelBar/` — контейнер, не git-репозиторий. Внутри два независимых репозитория:

- `app/` — это приложение. Remote `github.com/Clleo/BabelBar`, ветка `main`.
- `site/` — лендинг babelbar.app. Remote `github.com/Clleo/babelbar-site`, деплой через Cloudflare.

Объединять в монорепозиторий не нужно: разные пайплайны выпуска.
