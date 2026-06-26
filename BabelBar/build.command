#!/bin/bash
#
# BabelBar — сборка приложения в один клик.
# Дважды кликни по этому файлу в Finder.
# Готовый BabelBar.app появится на Рабочем столе.
#
set -e

# Перейти в папку, где лежит этот скрипт (где находится .xcodeproj)
cd "$(dirname "$0")"

echo "============================================"
echo "  Сборка BabelBar..."
echo "============================================"

# Проверка наличия Xcode
if ! xcodebuild -version >/dev/null 2>&1; then
  echo ""
  echo "❌ Не найден Xcode."
  echo "   Установи Xcode из Mac App Store, затем запусти этот файл снова."
  echo ""
  echo "   После установки Xcode один раз выполни в Терминале:"
  echo "     sudo xcodebuild -license accept"
  echo ""
  read -n 1 -s -r -p "Нажми любую клавишу, чтобы закрыть..."
  exit 1
fi

BUILD_DIR="./.build_output"
rm -rf "$BUILD_DIR"

# Сборка Release-конфигурации без подписи (для локального запуска)
xcodebuild \
  -project BabelBar.xcodeproj \
  -scheme BabelBar \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$BUILD_DIR/Build/Products/Release/BabelBar.app"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Сборка не удалась — BabelBar.app не найден."
  read -n 1 -s -r -p "Нажми любую клавишу, чтобы закрыть..."
  exit 1
fi

# Display name is BabelBar — deploy the bundle under that name so Finder/Dock match.
# (Only the Xcode target/scheme id stays "BabelBar" internally; product & bundle are BabelBar.)
#
# Куда положить готовый .app можно переопределить переменной BABELBAR_DEST
# (так делает release.command — он собирает во временную папку, чтобы НЕ засорять
# Рабочий стол). По умолчанию, при ручном запуске, кладём на Рабочий стол.
DEST="${BABELBAR_DEST:-$HOME/Desktop/BabelBar.app}"
rm -rf "$DEST" "$HOME/Desktop/BabelBar.app"   # drop the old-named copy if present
mkdir -p "$(dirname "$DEST")"
cp -R "$APP_PATH" "$DEST"

# Снять карантин и прочие расширенные атрибуты
xattr -cr "$DEST" 2>/dev/null || true

# Подписать СТАБИЛЬНОЙ подписью (Apple Development), если она есть.
# Это важно: ad-hoc подпись меняется при каждой сборке, из-за чего macOS
# сбрасывает выданные разрешения (Мониторинг ввода / Универсальный доступ),
# и хоткей ⌘+C+C перестаёт работать. Стабильная подпись решает это.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $2}')
ENT="BabelBar/BabelBar.entitlements"
if [ -n "$IDENTITY" ]; then
  echo "  Подпись сертификатом: $IDENTITY"
  codesign --force --deep --options runtime --entitlements "$ENT" --sign "$IDENTITY" "$DEST"
else
  echo "  Стабильный сертификат не найден — ad-hoc подпись (разрешения будут слетать)."
  codesign --force --deep --sign - "$DEST"
fi

# Тихий режим (его включает release.command): не показываем финальное окно
# и не открываем Finder — приложение здесь лишь промежуточный продукт для DMG.
if [ -n "$BABELBAR_QUIET" ]; then
  exit 0
fi

echo ""
echo "============================================"
echo "  ✅ Готово!"
echo "  BabelBar.app лежит на Рабочем столе."
echo "  Дважды кликни по нему, чтобы запустить."
echo "============================================"
echo ""
open -R "$DEST"

[[ -t 0 ]] && read -n 1 -s -r -p "Нажми любую клавишу, чтобы закрыть..."
exit 0
