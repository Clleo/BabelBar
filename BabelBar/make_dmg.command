#!/bin/bash
#
# BabelBar — упаковка в установочный .dmg.
# Дважды кликни этот файл. На Рабочем столе появится BabelBar.dmg:
# открыв его, пользователь видит иконку приложения и папку Applications,
# куда перетаскивает BabelBar для установки — как в обычных macOS-приложениях.
#
set -e
cd "$(dirname "$0")"

echo "============================================"
echo "  Сборка и упаковка BabelBar.dmg..."
echo "============================================"

# 1) Собрать подписанное приложение (кладётся на Рабочий стол как BabelBar.app).
#    Не прерываемся на коде возврата build.command — наличие .app проверяем ниже.
./build.command || true

APP="$HOME/Desktop/BabelBar.app"
if [ ! -d "$APP" ]; then
  echo "❌ Не найден $APP — сборка не удалась."
  [[ -t 0 ]] && read -n 1 -s -r -p "Нажми любую клавишу..."
  exit 1
fi

VOL="BabelBar"
DMG="$HOME/Desktop/BabelBar.dmg"
RW="$(mktemp -u).dmg"
STAGE="$(mktemp -d)"

# 2) Содержимое окна установки: приложение + ярлык на /Applications.
cp -R "$APP" "$STAGE/BabelBar.app"
ln -s /Applications "$STAGE/Applications"

# 3) Read-write образ, чтобы задать раскладку окна.
rm -f "$RW" "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
rm -rf "$STAGE"

DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | egrep '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="/Volumes/$VOL"

# 4) Раскладка окна (иконки крупные, приложение слева, Applications справа).
#    Требует разрешение «Автоматизация → Finder» (спросит один раз). Если откажешь —
#    DMG всё равно соберётся, просто без красивой раскладки.
osascript <<EOF || true
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 720, 460}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 112
    set text size of vo to 12
    set position of item "BabelBar.app" of container window to {140, 165}
    set position of item "Applications" of container window to {380, 165}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true

# 5) Сжать в финальный распространяемый DMG.
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"

echo ""
echo "============================================"
echo "  ✅ Готово!"
echo "  BabelBar.dmg лежит на Рабочем столе."
echo "  Открой его и перетащи BabelBar в Applications."
echo "============================================"
[[ -t 0 ]] && read -n 1 -s -r -p "Нажми любую клавишу, чтобы закрыть..."
exit 0
