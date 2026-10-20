# hablapp

Dictado por voz para cualquier app de tu Mac. Mantén **fn**, habla y suelta: el texto aparece donde está el cursor. Todo se procesa en tu Mac.

## Requisitos

- macOS 26 o posterior.
- Mac con Apple Silicon (M1 o posterior).
- Apple Intelligence es opcional. Sólo hace falta para el formato con IA; sin él, el dictado funciona igual.

## Instalar

1. Descargá [hablapp.zip](https://github.com/briascoi/hablapp/releases/latest/download/hablapp.zip).
2. Descomprimilo y mové **hablapp** a la carpeta Aplicaciones.
3. Al abrirla por primera vez, macOS la bloquea porque la app no está notarizada. Andá a **Ajustes del Sistema › Privacidad y seguridad**, buscá el aviso de hablapp y tocá **Abrir igualmente**.
4. Concedé los permisos de **Micrófono** y **Accesibilidad** cuando la app los pida.

Las actualizaciones siguientes se descargan y instalan desde la propia app.

## Compilar

Hace falta tener instaladas las herramientas de línea de comandos de Xcode.

```sh
cd app && ./build.sh
```

Deja la app en `app/build/hablapp.app`. Con `./build.sh install` además la copia a `~/Applications` y la abre. Si no tienes el certificado "hablapp Dev" en tu llavero, la app se firma ad-hoc.

## Atajos con Raycast y Atajos

hablapp responde a URLs `hablapp://`. En la app de Atajos usá la acción **Abrir URLs**; en Raycast, creá un **Quicklink** con la URL.

| URL | Qué hace |
| --- | --- |
| `hablapp://start` | Empieza a dictar en manos libres |
| `hablapp://stop` | Termina el dictado y pega |
| `hablapp://toggle` | Empieza o termina, según el estado |
| `hablapp://cancel` | Descarta el dictado en curso |
| `hablapp://paste-last` | Pega la última transcripción |
| `hablapp://transform?name=Pulir` | Aplica el transform indicado al texto seleccionado (espacios como `%20`) |

También se pueden probar desde la Terminal: `open "hablapp://toggle"`.

## Privacidad

El audio y el texto se procesan en tu Mac y no salen de ella. No hay cuentas ni analítica. La única conexión a internet de la app es para consultar si hay versiones nuevas en GitHub.

## Apoyar

hablapp es gratis y lo seguirá siendo. Si te ahorra tiempo, puedes [invitarme un cafecito](https://cafecito.app/briascoi).

## Licencia

MIT. Ver [LICENSE](LICENSE).
