#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Battery Info"
DIST="$ROOT/dist/${APP_NAME}.app"
INSTALL="$HOME/Applications/${APP_NAME}.app"
ICONSET="$ROOT/build/AppIcon.iconset"
ICON="$ROOT/build/AppIcon.icns"

mkdir -p "$ROOT/build"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

echo "→ Иконка"
swiftc -swift-version 5 -O -framework AppKit -o "$ROOT/build/make-icon" "$ROOT/Scripts/make-icon.swift"
"$ROOT/build/make-icon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICON"

echo "→ Сборка"
rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS" "$DIST/Contents/Resources"
cp "$ROOT/App/Info.plist" "$DIST/Contents/Info.plist"
cp "$ICON" "$DIST/Contents/Resources/AppIcon.icns"

clang -O2 -c -o "$ROOT/build/PrivilegedShell.o" "$ROOT/Sources/PrivilegedShell.c"

swiftc \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -framework AppKit \
  -framework SwiftUI \
  -framework IOKit \
  -framework ServiceManagement \
  -framework Security \
  -o "$DIST/Contents/MacOS/${APP_NAME}" \
  "$ROOT"/Sources/*.swift \
  "$ROOT/build/PrivilegedShell.o"

codesign --force --sign - --identifier com.strelnikov.batteryinfo "$DIST"

echo "→ Установщик"
"$ROOT/Scripts/make-dmg.sh"

echo "→ Показания батареи"
"$DIST/Contents/MacOS/${APP_NAME}" --print

echo "→ Установка в ~/Applications"
mkdir -p "$HOME/Applications"
if pgrep -x "Battery Info" >/dev/null; then
  killall "Battery Info" || true
  sleep 0.4
fi
rm -rf "$INSTALL"
ditto "$DIST" "$INSTALL"
xattr -cr "$INSTALL" || true
codesign --force --sign - --identifier com.strelnikov.batteryinfo "$INSTALL"

echo "→ Запуск"
open "$INSTALL"
echo "Готово: $INSTALL"
