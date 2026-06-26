#!/bin/bash
#
# BabelBar — выпуск релиза.
# Дважды кликни этот файл (или запусти из проекта). Он:
#   1. поднимает версию (semver, patch +1): 1.0.0 → 1.0.1 → 1.0.2 …  (файл VERSION в корне проекта)
#   2. прописывает эту версию в проект (MARKETING_VERSION / CURRENT_PROJECT_VERSION)
#   3. собирает и подписывает приложение (через build.command)
#   4. пакует установочный DMG «BabelBar-<версия>.dmg» В КОРЕНЬ ПРОЕКТА (рядом с предыдущими)
#
set -e
cd "$(dirname "$0")"                 # .../BabelBar  (тут .xcodeproj и build.command)
ROOT="$(cd .. && pwd)"               # корень проекта (.../BabelBar)
VFILE="$ROOT/VERSION"

# 1) Версия релиза.
#    Передай номер аргументом:  ./release.command 1.0.2
#    Без аргумента — автоинкремент patch (1.0.1 → 1.0.2) как запасной вариант.
cur="$(tr -d ' \n\r' < "$VFILE" 2>/dev/null)"; [ -z "$cur" ] && cur="1.0.0"
if [ -n "$1" ]; then
    VER="$1"
else
    IFS='.' read -r MA MI PA <<< "$cur"
    MA=${MA:-1}; MI=${MI:-0}; PA=${PA:-0}
    VER="$MA.$MI.$((PA + 1))"
fi
echo "$VER" > "$VFILE"
echo "============================================"
echo "  Релиз BabelBar $cur → $VER"
echo "============================================"

# 2) Синхронизировать версию приложения с номером релиза.
PBX="BabelBar.xcodeproj/project.pbxproj"
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VER;/g" "$PBX"

# 3) Собрать + подписать ВО ВРЕМЕННУЮ ПАПКУ (не на Рабочем столе!).
#    Готовый .app здесь — лишь промежуточный продукт для упаковки в DMG,
#    поэтому собираем в staging-папку и потом её удаляем — Рабочий стол чистый.
STAGE="$(mktemp -d)"
APP="$STAGE/BabelBar.app"
BABELBAR_DEST="$APP" BABELBAR_QUIET=1 ./build.command || true
if [ ! -d "$APP" ]; then
  echo "❌ Сборка не удалась — $APP не найден."
  rm -rf "$STAGE"
  [[ -t 0 ]] && read -n 1 -s -r -p "Нажми любую клавишу…"
  exit 1
fi

# 4) Упаковать DMG в корень проекта (перетащи BabelBar в Applications).
DMG="$ROOT/BabelBar-$VER.dmg"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "BabelBar" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "============================================"
echo "  ✅ Готово: BabelBar-$VER.dmg"
echo "  Лежит в корне проекта: $DMG"
echo "============================================"
open -R "$DMG"
[[ -t 0 ]] && read -n 1 -s -r -p "Нажми любую клавишу, чтобы закрыть…"
exit 0
