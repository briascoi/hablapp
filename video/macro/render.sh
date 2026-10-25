#!/bin/zsh
# Renderiza la prueba en 4K con cada música candidata (m1, m2) y deja index.html en m1.
cd "${0:A:h}"
for t in m1 m2; do
  sed -i '' "s/mix-m[12]\.wav/mix-$t.wav/; s/const TRACK = \"m[12]\"/const TRACK = \"$t\"/" index.html
  npx --yes hyperframes@0.8.193 render -c index.html --resolution=4k -q delivery -o renders/macro-$t.mp4 --workers 2 --quiet || exit 1
done
sed -i '' "s/mix-m[12]\.wav/mix-m1.wav/; s/const TRACK = \"m[12]\"/const TRACK = \"m1\"/" index.html
