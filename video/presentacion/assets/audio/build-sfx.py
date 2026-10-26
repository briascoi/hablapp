#!/usr/bin/env python3
"""Arma assets/audio/sfx.wav: cada efecto en la acción que se ve, un frame después."""
import os, subprocess

SFX = os.path.expanduser("~/.claude/skills/media-use/audio/assets/sfx")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sfx.wav")
FRAME = 1 / 30

# (segundo global, archivo, ganancia dB, recorte opcional en s)
CUES = [
    # gancho
    (0.035, "key-press", 0, None), (4.0, "whoosh-short", -10, None), (4.6, "key-press", 0, None),
    (8.12, "pop", -6, None),
    (9.95, "whoosh-short", -10, None), (10.455, "key-press", -2, None), (11.285, "pop", -7, None),
    (11.47, "whoosh-short", -10, None), (11.98, "key-press", -2, None), (12.81, "pop", -7, None),
    (12.99, "whoosh-short", -10, None), (13.505, "key-press", -2, None), (14.335, "pop", -7, None),
    (15.45, "key-press", 0, None),
    # revela
    (16.305, "impact-bass-1", -12, None),
    *[(19.355 + i * 0.127, "click-soft", -13, None) for i in range(1, 9)],
    (20.375, "pop", -6, None), (21.905, "whoosh-short", -9, None),
    # estilo
    (23.455, "click-soft", -8, None), (26.275, "click-soft", -8, None), (28.305, "click-soft", -8, None),
    (30.025, "whoosh-short", -9, None),
    # manos
    (30.845, "key-press", 0, None), (31.105, "key-press", 0, None), (31.385, "pop", -6, None),
    (33.845, "click", -3, None), (33.965, "whoosh-cinematic", -13, 1.4),
    # privada
    (35.905, "pop", -10, None),
    (36.635, "click-soft", -14, None), (37.655, "click-soft", -14, None), (38.675, "click-soft", -14, None),
    (40.005, "whoosh-cinematic", -12, 1.4),
    # comando
    (42.315, "key-press", -1, None), (44.785, "sparkle", -13, None), (46.315, "whoosh-short", -9, None),
    # transforms
    (47.065, "key-press", 0, None), (47.573, "key-press", 0, None), (48.081, "key-press", 0, None),
    (48.495, "click", -4, None), (48.845, "whoosh-short", -10, None), (49.865, "click-soft", -9, None),
    (50.885, "sparkle", -13, None), (53.065, "pop", -9, None), (53.315, "pop", -9, None),
    (54.505, "whoosh-short", -9, None),
    # contexto
    (56.985, "pop", -6, None), (58.595, "whoosh-short", -9, None),
    # montaje
    (59.805, "click-soft", -10, None), (60.625, "click-soft", -10, None), (61.445, "click-soft", -10, None),
    (62.385, "typing", 0, 0.45),
    # cierre
    (63.085, "impact-bass-2", -11, None), (64.085, "whoosh-short", -12, None), (64.835, "chime", -10, None),
    (67.155, "pop", -8, None), (69.185, "click", -2, None),
]
RISER = (60.085, 7.0, -12)  # cola del riser (desde 7 s) que termina en el golpe de 63.085

inputs, chains = [], []
for i, (t, name, db, trim) in enumerate(CUES):
    inputs += ["-i", f"{SFX}/{name}.mp3"]
    tr = f"atrim=0:{trim},afade=t=out:st={trim - 0.3}:d=0.3," if trim else ""
    ms = int(round((t + FRAME) * 1000))
    chains.append(f"[{i}:a]{tr}volume={db}dB,adelay={ms}|{ms}[c{i}]")
r = len(CUES)
inputs += ["-i", f"{SFX}/riser.mp3"]
st, cut, db = RISER
chains.append(f"[{r}:a]atrim={cut},asetpts=PTS-STARTPTS,afade=t=in:d=0.6,volume={db}dB,adelay={int(st*1000)}|{int(st*1000)}[c{r}]")
mix = "".join(f"[c{i}]" for i in range(r + 1))
chains.append(f"{mix}amix=inputs={r + 1}:normalize=0,apad=whole_dur=73.93,atrim=0:73.93[out]")

subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *inputs,
                "-filter_complex", ";".join(chains), "-map", "[out]", "-ar", "48000", "-ac", "2", OUT], check=True)
print(OUT)
