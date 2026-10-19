#!/bin/zsh
# Publica una release. Uso: ./release.sh [--dry-run] [--notes "texto"] X.Y.Z
# Requiere gh autenticado y el certificado "hablapp Dev". --dry-run imprime cada comando sin ejecutarlo.
set -euo pipefail
cd "$(dirname "$0")"

DRY=0; NOTES=""; VER=""
while (( $# )); do
  case "$1" in
    --dry-run) DRY=1 ;;
    --notes) NOTES="$2"; shift ;;
    *) VER="$1" ;;
  esac
  shift
done
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Uso: ./release.sh [--dry-run] [--notes \"texto\"] X.Y.Z" >&2; exit 1 }

# Ejecuta (o sólo imprime en --dry-run) un comando.
run() { if (( DRY )); then print -r -- "+ ${(q-)@}"; else "$@"; fi }

# 1. Árbol limpio
if [[ -n "$(git status --porcelain)" ]]; then
  (( DRY )) && echo "(aviso: árbol git sucio; una release real abortaría)" || { echo "Árbol git sucio: commiteá o descartá antes." >&2; exit 1 }
fi

# 2. Versión en Info.plist (+1 a CFBundleVersion)
PLIST=Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
run /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$PLIST"
run /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

# 3. Compilar y verificar firma: con firma ad-hoc se aborta (rompería el updater y los permisos)
run ./build.sh
run codesign --verify --deep --strict build/hablapp.app
if (( DRY )); then
  echo '+ (verifica que "codesign -dr -" no sea ad-hoc: debe incluir "certificate leaf"; si no, abortar)'
else
  codesign -dr - build/hablapp.app 2>&1 | grep -q "certificate leaf" || { echo 'Firma ad-hoc: falta el certificado "hablapp Dev". Abortado.' >&2; exit 1 }
fi

# 4. Zip y checksum
run ditto -c -k --keepParent build/hablapp.app build/hablapp.zip
run shasum -a 256 build/hablapp.zip

# 5. Commit, tag, push y release
run git commit -am "Release v$VER"
run git tag -a "v$VER" -m "hablapp $VER"
run git push --follow-tags
if [[ -n "$NOTES" ]]; then
  run gh release create "v$VER" build/hablapp.zip --title "hablapp $VER" --notes "$NOTES"
else
  NF=$( (( DRY )) && echo "<archivo-de-notas>" || mktemp )
  (( DRY )) || { ${EDITOR:-nano} "$NF"; }
  run gh release create "v$VER" build/hablapp.zip --title "hablapp $VER" --notes-file "$NF"
fi
