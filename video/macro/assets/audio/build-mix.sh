#!/bin/zsh
# Mezcla de la prueba de 20 s: música + efectos en los anclajes de cada tema (los mismos de index.html).
# Uso: ./build-mix.sh  →  mix-m1.wav y mix-m2.wav
zmodload zsh/mathfunc; cd "${0:A:h}"
mix() { # tema press land title
  local ms=(); for s in $2 $3 $4; do ms+=$(( int(${s} * 1000) )); done
  ffmpeg -y -hide_banner -loglevel error -i macro-$1.mp3 -i key-press.mp3 -i whoosh-short.mp3 -i impact-bass-1.mp3 -filter_complex "
    [0:a]atrim=0:20,asetpts=N/SR/TB,volume=0.85[m];
    [1:a]adelay=${ms[1]}|${ms[1]},volume=0.9[k];
    [2:a]adelay=$(( ms[1] + 150 ))|$(( ms[1] + 150 )),volume=0.5[w];
    [3:a]asplit[i1][i2];[i1]adelay=${ms[2]}|${ms[2]},volume=0.55[a];[i2]adelay=${ms[3]}|${ms[3]},volume=0.7[b];
    [m][k][w][a][b]amix=inputs=5:normalize=0:duration=first,loudnorm=I=-16:TP=-1.5:LRA=11,volume=-1.6dB,afade=t=out:st=18.4:d=1.6,aresample=48000[o]" \
    -map "[o]" -t 20 -c:a pcm_s16le mix-$1.wav
}
# loudnorm en una pasada deja ~-14,4 LUFS en 20 s; el -1,6 dB lo baja a -16.
mix m1 1.65 8.07 14.49
mix m2 1.76 8.45 13.6
for f in mix-m*.wav; do echo "$f $(ffmpeg -hide_banner -nostats -i $f -af ebur128=peak=true -f null - 2>&1 | grep -E 'I:|Peak:' | tail -2 | tr -s ' \n' ' ')"; done
