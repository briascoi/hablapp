#!/bin/zsh
# Compila hablapp.app. Uso: ./build.sh            (deja build/hablapp.app)
#                           ./build.sh install    (además la copia a ~/Applications y la abre)
set -euo pipefail
cd "$(dirname "$0")"
APP=build/hablapp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"

if [[ ! -f build/AppIcon.icns ]]; then
  ICONSET=build/AppIcon.iconset
  mkdir -p "$ICONSET"
  swift make-icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/"

swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -o "$APP/Contents/MacOS/hablapp" Sources/*.swift
# Firma con el certificado autofirmado "hablapp Dev" (llavero de inicio de sesión): el requisito designado
# queda fijo entre compilaciones y macOS conserva los permisos. Si no está, cae a firma ad-hoc.
SIGN=$(security find-identity -p codesigning | awk '/"hablapp Dev"/{print $2; exit}')
codesign --force --sign "${SIGN:--}" --identifier com.isma.hablapp "$APP"
echo "Listo: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x hablapp 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/hablapp.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/hablapp.app
fi
