#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Battery Info"
SRC="$ROOT/dist/${APP_NAME}.app"
OUT="$ROOT/dist/${APP_NAME}.dmg"
STAGE="$(mktemp -d)"
RW="$(mktemp -d)/rw.dmg"

cleanup() {
  if [[ -d "/Volumes/${APP_NAME}" ]]; then
    hdiutil detach "/Volumes/${APP_NAME}" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE" "$(dirname "$RW")"
}
trap cleanup EXIT

if [[ ! -d "$SRC" ]]; then
  echo "Сначала соберите приложение: ./build.sh" >&2
  exit 1
fi

mkdir -p "$ROOT/dist"
rm -f "$OUT"

ditto "$SRC" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" << 'EOF'
Battery Info

Drag Battery Info onto the Applications folder, then open it from there.

The first time you open it, macOS says the app is not safe and offers to move it to the Trash.
Do not delete it.

Open System Settings → Privacy & Security and choose Open Anyway.


Перетащите Battery Info в папку «Программы» и откройте его оттуда.

При первом запуске macOS напишет, что приложение небезопасно, и предложит удалить его.
Удалять не нужно.

Откройте «Системные настройки» → «Конфиденциальность и безопасность» и нажмите «Все равно открыть».
EOF

hdiutil create -size 80m -fs HFS+ -volname "$APP_NAME" -ov "$RW" >/dev/null
hdiutil attach -readwrite -noverify -noautoopen "$RW" >/dev/null
cp -R "$STAGE/${APP_NAME}.app" "/Volumes/${APP_NAME}/"
cp "$STAGE/Read Me.txt" "/Volumes/${APP_NAME}/"
ln -s /Applications "/Volumes/${APP_NAME}/Applications"

osascript << EOF || true
tell application "Finder"
  tell disk "${APP_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {240, 120, 840, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set position of item "${APP_NAME}.app" of container window to {150, 150}
    set position of item "Applications" of container window to {430, 150}
    set position of item "Read Me.txt" of container window to {290, 300}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

sync
hdiutil detach "/Volumes/${APP_NAME}" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

echo "Готово: $OUT"
