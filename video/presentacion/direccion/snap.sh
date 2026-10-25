#!/bin/zsh
# Captura cada style frame en Chrome real a 1920x1080.
for f in "$@"; do
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu-sandbox --hide-scrollbars \
    --window-size=1920,1080 --force-device-scale-factor=1 --virtual-time-budget=1500 \
    --screenshot="${f:r}.png" "file://$PWD/$f" 2>/dev/null
  shot "${f:r}.png" >/dev/null 2>&1
done
ls -la *-lite.jpg
