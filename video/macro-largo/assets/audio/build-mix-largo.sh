#!/bin/zsh
# Mezcla del video largo: macro-l4 + voz + efectos en la misma grilla que index.html (downbeats 1,453 + 1,905·k).
# Dos pasadas: mezcla cruda, se mide y se lleva a -15,4 LUFS (el MP4 final queda en -16) con limitador a -1,5 dBTP.
# Uso: ./build-mix-largo.sh  →  mix-largo.wav
zmodload zsh/mathfunc; cd "${0:A:h}"
B() { echo $(( 1.453 + $1 * 1.905 )); }
BEAT=$(( 1.905 / 4 ))
FX=( # archivo segundo volumen
  key-press $(B 1) 0.9   whoosh-short $(( $(B 1) + 0.15 )) 0.5
  impact-bass-1 $(B 4) 0.45
  whoosh-short $(B 7) 0.35   click-soft $(( $(B 7) + BEAT * 2 )) 0.5   pop $(B 8.5) 0.35
  key-press $(B 10) 0.9   key-press $(( $(B 10) + BEAT / 2 )) 0.9   key-press $(( $(B 13) - BEAT )) 0.8
  whoosh-short $(B 13) 0.35   click-soft $(( $(B 13) + 0.4 )) 0.4   whoosh-short $(( $(B 14) + BEAT * 3 )) 0.45
  whoosh-short $(B 17) 0.3
  key-press $(( $(B 19) - BEAT / 2 )) 0.8   key-press $(( $(B 19) - BEAT / 4 )) 0.8   key-press $(B 19) 0.9   impact-bass-1 $(B 19) 0.4
  whoosh-short $(B 21) 0.3   sparkle $(B 22.5) 0.3
  impact-bass-1 $(B 28) 0.5
  whoosh-short $(( $(B 28) + BEAT * 3 )) 0.3   whoosh-short $(( $(B 28) + BEAT * 6 )) 0.3   whoosh-short $(( $(B 28) + BEAT * 10 )) 0.3
  impact-bass-2 $(B 32) 0.7   click-soft $(( $(B 33) + BEAT )) 0.35
)
ins=(-i macro-l4.mp3) g="[0:a]atrim=0:72,asetpts=N/SR/TB,volume=0.85[m0];" labels="[m]" n=1
for f t v in $FX; do
  ms=$(( int(t * 1000) )); ins+=(-i $f.mp3); g+="[${n}:a]adelay=$ms|$ms,volume=${v}[f$n];"; labels+="[f$n]"; n=$(( n + 1 ))
done
# Subida antes del cierre: los últimos 3,5 s del riser terminan justo en el downbeat 32.
ms=$(( int(($(B 32) - 3.5) * 1000) )); ins+=(-i riser.mp3); g+="[${n}:a]atrim=6.5:10,asetpts=N/SR/TB,adelay=$ms|$ms,volume=0.35[f$n];"; labels+="[f$n]"; n=$(( n + 1 ))
# Voz de Isma (ElevenLabs PVC): mismos inicios que VH, VC y VG en index.html. La música baja mientras habla.
VOZ=( v-hola $(( $(B 2) + 0.15 ))  v-corto $(B 14)  v-gracias $(( $(B 21) + 0.6 )) ) vl=""
for f t in $VOZ; do
  ms=$(( int(t * 1000) )); ins+=(-i voces/$f.mp3); g+="[${n}:a]aresample=48000,adelay=${ms}|${ms}[${f}];"; vl+="[${f}]"; n=$(( n + 1 ))
done
g+="${vl}amix=inputs=3:normalize=0,highpass=f=90,volume=${VOL_VOZ:-4},apad=whole_dur=72,asplit[vo][vk];"
g+="[m0][vk]sidechaincompress=threshold=0.01:ratio=12:attack=15:release=350[m];"
labels+="[vo]"
# Las tres tomas de voz entran como una sola etiqueta: n - 2 entradas en la mezcla final.
g+="${labels}amix=inputs=$(( n - 2 )):normalize=0:duration=first,afade=t=out:st=70.4:d=1.6,aresample=48000"
ffmpeg -y -hide_banner -loglevel error $ins -filter_complex "${g}[o]" -map "[o]" -t 72 -c:a pcm_s24le crudo.wav || exit 1
I=$(ffmpeg -hide_banner -nostats -i crudo.wav -af ebur128 -f null - 2>&1 | grep -E '^\s+I:' | tail -1 | awk '{print $2}')
ffmpeg -y -hide_banner -loglevel error -i crudo.wav -af "volume=$(( -15.4 - I ))dB,alimiter=limit=0.84:level=false" -c:a pcm_s16le mix-largo.wav && rm crudo.wav
echo "crudo $I LUFS → $(ffmpeg -hide_banner -nostats -i mix-largo.wav -af ebur128=peak=true -f null - 2>&1 | grep -E 'I:|Peak:' | tail -2 | tr -s ' \n' ' ')"
