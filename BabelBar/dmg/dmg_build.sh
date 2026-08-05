#!/bin/bash
#
# Сборка оформленного установочного DMG.
#
#   dmg_build.sh <путь-к-BabelBar.app> <путь-к-итоговому.dmg> [имя-тома]
#
# Что получает пользователь: окно 660×420 с фирменным фоном, слева иконка
# приложения, справа папка Applications, между ними надпись «drag and drop»
# и стрелка. Иконки настоящие (Finder рисует их сам) — на фоне только подложка.
#
# Раскладка задаётся через Finder и требует разрешения «Автоматизация → Finder»
# (система спросит один раз). Если разрешение не дать — DMG всё равно соберётся,
# просто без оформления.
#
set -e

APP="${1:?нужен путь к .app}"
DMG="${2:?нужен путь к итоговому .dmg}"
VOL="${3:-BabelBar}"

HERE="$(cd "$(dirname "$0")" && pwd)"
BG_TIFF="$HERE/background.tiff"

# Фон — генерируемый файл; если его нет (или изменён исходник), рисуем заново.
if [ ! -f "$BG_TIFF" ] || [ "$HERE/make_background.swift" -nt "$BG_TIFF" ]; then
  echo "  • рисую фон окна установки…"
  swift "$HERE/make_background.swift" "$HERE" >/dev/null
  tiffutil -cathidpicheck "$HERE/background.png" "$HERE/background@2x.png" -out "$BG_TIFF" >/dev/null
fi

STAGE="$(mktemp -d)"
RW="$(mktemp -u).dmg"
trap 'rm -rf "$STAGE" "$RW"' EXIT

# 1) Содержимое тома: приложение, ярлык на /Applications, скрытый фон.
cp -R "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BG_TIFF" "$STAGE/.background/background.tiff"

# Иконка самого тома — иконка приложения (видно в Finder и на рабочем столе).
ICNS="$APP/Contents/Resources/AppIcon.icns"
[ -f "$ICNS" ] && cp "$ICNS" "$STAGE/.VolumeIcon.icns"

# 2) Read-write образ: Finder может писать раскладку только в него.
#    Запас 40 МБ — иначе hdiutil делает том впритык и Finder падает на записи .DS_Store.
SIZE_KB=$(( $(du -sk "$STAGE" | awk '{print $1}') + 40000 ))
rm -f "$RW"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ \
  -format UDRW -size "${SIZE_KB}k" -ov "$RW" >/dev/null

DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | egrep '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="/Volumes/$VOL"

# Пометить том как имеющий свою иконку (атрибут C у корня).
if [ -f "$MOUNT/.VolumeIcon.icns" ]; then
  SetFile -a C "$MOUNT" 2>/dev/null || true
fi

# 3) Раскладка окна. Позиции иконок обязаны совпадать с центрами из
#    make_background.swift: приложение {165,170}, Applications {495,170}.
osascript <<EOF || echo "  ⚠️  Finder не дал оформить окно — DMG собран без раскладки."
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- Боковая панель входит в bounds: с ней окно оказывается на её ширину шире
    -- фона, и картинка съезжает. Сначала убрать панель, только потом задавать размер.
    set sidebar width of container window to 0
    set the bounds of container window to {240, 140, 900, 560}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 128
    set text size of vo to 13
    set label position of vo to bottom
    set background picture of vo to file ".background:background.tiff"
    set position of item "$(basename "$APP")" of container window to {165, 170}
    set position of item "Applications" of container window to {495, 170}
    -- Повторно: Finder любит пересчитать размер после смены вида и фона.
    set the bounds of container window to {240, 140, 900, 560}
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true

# 4) Сжать в распространяемый образ (только чтение).
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

echo "  ✅ DMG собран: $DMG"
