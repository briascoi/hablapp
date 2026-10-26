# REVIEW · hablapp, video de presentación

## Estado

- `hyperframes lint`: 0 errores, 0 advertencias.
- `hyperframes check`: ok, 0 errores. Quedan advertencias aceptadas (abajo).
- Frames revisados en snapshots: 0, 1.3, 2.3, 4.5, 6.5, 8.9, 10.9, 12.5, 14, 15.2, 16.1, 17.5, 20.3, 24, 27, 29.5, 30.3, 30.9, 31.7, 33.9, 34.8, 36.5, 39.5, 40.2, 42.3, 44.2, 44.9, 45.9, 47.5, 48.6, 50.2, 52.4, 53.8, 55.2, 56.9, 58, 59.6, 60.4, 61.3, 62.6, 63.4, 64, 64.6, 66.6, 69.3 y 71.78 s.

## Corregido en la revisión

- Se perdía el último espacio de cada título armado por palabras ("Manoslibres", "tuMac"): el espacio ahora va dentro de cada caja (`HB.words`).
- "Gracias, Itziar." se dibujaba con el punto delante del nombre: el resaltado pasó a ser inline.
- La puntuación naranja del correo no se veía porque el tween apuntaba a nodos que aún no existían.
- El título de la nota tapaba el párrafo en Modo comando.
- Las ondas de la pantalla del Mac seguían visibles durante la entrada a Modo comando.
- Solape de tweens en las teclas de Transforms (`gsap_tween_tail`).
- "Desafío de 100 palabras por día" dejaba "día" solo en la segunda línea.
- Títulos de ventana a 30 px para pasar el piso de lectura.

## Advertencias aceptadas

- `text_below_floor` en el zoom out de cuatro apps (14,3 a 16,3 s): las ventanas están a escala 0,42 a propósito, es textura.
- `line_unread` en los textos de ejemplo dictados, el tragamonedas de apps y el montaje del Hub: son demostración de la interfaz, no texto para leer completo. Los títulos de cada escena sí cumplen su tiempo.

## Fuentes

SF Pro, SF Mono y New York no van en el repo porque son del sistema de Apple. Para renderizar en un Mac:

```bash
cp /System/Library/Fonts/{SFNS,SFNSMono,NewYork}.ttf assets/fonts/
```

## Sonido

- Música: ElevenLabs (music_v2_5, instrumental, 118 BPM), recortada a 73,93 s con fade de 3 s.
- Efectos: `assets/audio/build-sfx.py` arma `sfx.wav` con 64 efectos (63 golpes y la cola de un riser hacia el remate), cada uno un frame después de su acción.
- Mezcla medida (no escuchada): -16,4 LUFS integrados, pico real -1,3 dBFS, con la música a 0,78.
