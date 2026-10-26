#!/bin/zsh
# Dos tomas largas (74 s), una tras otra (en paralelo la API devuelve 502).
# Segunda tanda, más movida: l1 y l2 (estilo m1, tensas) quedaron cortas de energía.
# Uso: ./gen-largo.sh  →  macro-l3.mp3 y macro-l4.mp3 (la key sale del Llavero, servicio ACE_MUSIC_API_KEY)
cd "${0:A:h}"
export ACE_MUSIC_API_KEY=${ACE_MUSIC_API_KEY:-$(security find-generic-password -s ACE_MUSIC_API_KEY -w 2>/dev/null)}
[ -n "$ACE_MUSIC_API_KEY" ] || { echo "Falta ACE_MUSIC_API_KEY (ni en el entorno ni en el Llavero)"; exit 1; }
P="upbeat energetic electronic pop, driving four on the floor kick from the first second, 124 bpm, bright plucky synth arpeggios, warm analog bass, claps and crisp hi-hats, constant forward motion, riser into a bigger chorus at 22 seconds, short filtered break at 44 seconds, explosive drop at 50 seconds, final big hit at 62 seconds then warm chord fade out, modern tech product launch, confident and fun, instrumental"
for n in l3 l4; do python3 acemusic.py macro-$n "$P" 74 || echo "Falló $n"; done
