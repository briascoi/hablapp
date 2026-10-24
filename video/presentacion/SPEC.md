# SPEC · hablapp, video de presentación

GOAL:    que quien lo vea entienda en un vistazo que hablapp dicta en cualquier app del Mac, en local, con estilo por app, comandos y transforms, y quiera descargarla gratis.
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps, sin locución, música + SFX, español neutro (tú, como la landing).
TIME:    74 s x 30 = 2220 frames. Música 118 BPM, beat 0,508 s (15,25 frames), compás 2,03 s. Downbeats: 0.035 + n·2.0335.

LOOK:    tokens de la app (Theme.swift / docs/style.css):
         ground #F3F1EC, card #FCFBF9, line #E6E3DD, ink #1C1B1A, muted #6B675F,
         accent #7B4FC0 (soft #EFE7FB) sólo en modo comando y una palabra por plano,
         fn #F4A647 (borde #B86E10, texto #2A1A00) en la tecla y en el mundo de la revelación,
         mundo oscuro #171615 / card #21201E con tinta #EDEBE7 sólo en privacidad,
         degradé de Transforms #1F3B3E → #2F5D62 → #6B4A33 (el hero real de la app).
         Display: New York 400, 96–150 px, tracking -1%. UI: SF Pro 400/500/600, mínimo 28 px.
         Material: la UI real de hablapp a 2–2,5x; tarjetas radio 24–28 px, borde 2 px line,
         sombra 0 2px 4px rgba(28,27,26,.06) + 0 24px 80px rgba(28,27,26,.10). Grano 3%.
OBJECTS: la píldora negra (FlowBar.swift: cápsula negra 90%, borde blanco 18%, barras de 3 px a 2,5x),
         la tecla fn naranja (Key de Theme.swift), las tarjetas de Estilo y Transforms con su copy real,
         el ícono (geometría de make-icon.swift: squircle oscuro, 7 barras crema, la quinta naranja).
MOTION:  llegadas expo.out / power4.out 0,5–0,7 s; cámara power2.inOut 0,6 s; salidas power3.in 0,3 s;
         resortes back.out(1.4) sólo en posición y escala; palabras 0,08 s de stagger; letras 0,03 s.
         Motion blur de render activado en el root.
SHOTS:   ver tabla de escenas en index.html (cada host lleva su ventana). Cortes en downbeats:
         0 gancho · 16.3 revelación · 22.4 estilo · 30.5 manos libres · 34.6 privacidad ·
         40.7 comando · 46.8 transforms · 55.0 contexto · 59.0 montaje · 63.1 payoff · 65.1 cierre.
BANNED:  vacío oscuro con cosas chicas flotando; glow, partículas, orbes; degradés morados; glass;
         tres tarjetas en fila como lista de features (las de Estilo son una sola idea que cambia);
         todo entrando con fade + slide-up; títulos que se mueven después de aterrizar;
         logo en una esquina; UI inventada (todo label sale del código de la app);
         cifras inventadas (los ejemplos de texto son ilustrativos y no hay métricas).
QA:      1.0 s (tecla + píldora + "Mantén fn"), 8 s (texto pegado en el correo), 17.5 s (revelación),
         26 s (estilo), 37 s (privacidad), 44 s (comando), 50 s (transforms), 57 s (contexto),
         63.5 s (payoff), 71 s (cierre con CTA).
