# hablapp

Dictado por voz para cualquier app de tu Mac. Mantén **fn**, habla y suelta: el texto aparece donde está el cursor. La transcripción se procesa en tu Mac. La mejora de prompts por API es opcional y utiliza tu propia cuenta.

## Requisitos

- macOS 26 o posterior.
- Mac con Apple Silicon (M1 o posterior).
- Apple Intelligence es opcional. Sólo hace falta para el formato con IA; sin él, el dictado funciona igual.

## Instalar

1. Descargá [hablapp.zip](https://github.com/briascoi/hablapp/releases/latest/download/hablapp.zip).
2. Descomprimilo y mové **hablapp** a la carpeta Aplicaciones.
3. Al abrirla por primera vez, macOS la bloquea porque la app no está notarizada. Andá a **Ajustes del Sistema › Privacidad y seguridad**, buscá el aviso de hablapp y tocá **Abrir igualmente**.
4. Concedé los permisos de **Micrófono** y **Accesibilidad** cuando la app los pida.

La búsqueda automática de actualizaciones viene activada. Hablapp consulta GitHub al abrirse o al reactivar el Mac, como máximo una vez al día, y muestra un aviso cuando hay una versión nueva. Tú decides cuándo descargarla, instalarla y reiniciar. Puedes desactivar la búsqueda en **Ajustes › Acerca de**; se respeta cualquier elección anterior.

## Compilar

Hace falta tener instaladas las herramientas de línea de comandos de Xcode.

```sh
cd app && ./build.sh
```

Deja la app en `app/build/hablapp.app`. Con `./build.sh install` además la copia a `~/Applications` y la abre. Si no tienes el certificado "hablapp Dev" en tu llavero, la app se firma ad-hoc.

## Formato por aplicación

En **Transforms › Transform por app**, elige **Agregar app** y asigna un transform a cada aplicación. Puedes usar, por ejemplo, «Prompt engineer» en ChatGPT y Claude, y crear un transform con tus instrucciones de formato para WhatsApp.

Las aplicaciones sin regla usan el **Transform general**. Elige **Ninguno** para conservar el formato habitual del dictado en una aplicación concreta. Las reglas se guardan automáticamente. El interruptor de Transforms permite desactivar tanto los atajos como los transforms automáticos. Para aplicar un transform al texto seleccionado, usa **Control + Command + 1 a 9**. El interruptor **Atajos de teclado** permite desactivar sólo estos atajos y conservar los transforms automáticos. Las combinaciones con Option quedan disponibles para escribir caracteres.

También puedes asignar reglas para ChatGPT, Claude y WhatsApp en el navegador. El servicio tiene prioridad sobre la regla del navegador. Hablapp lo reconoce por la dirección que expone Accesibilidad o, si no está disponible, por la marca en el título de la pestaña. Si no logra reconocerlo, usa la regla del navegador o el general. Los transforms locales con IA requieren Apple Intelligence.

El preset **Prompt engineer** mejora y estructura lo dictado con tu propia API de OpenAI. En **Ajustes › Mejora de prompts**, ingresa tu clave y pulsa **Guardar y activar**. La clave se almacena en el Llavero de macOS de tu usuario, sin incorporarse al paquete de la app. Cada persona utiliza y paga su propia cuenta. Hablapp no incluye saldo ni una clave compartida; una suscripción a ChatGPT no incluye automáticamente consumo de API.

La función viene desactivada. Sin activarla, las reglas de Prompt engineer conservan el formato local del dictado. Los otros transforms siguen usando Apple Intelligence. Si una mejora por API falla o no supera los controles de cifras y condiciones, se conserva el dictado y se muestra un aviso. Los controles son parciales y no garantizan fidelidad semántica completa.

La mejora utiliza GPT-5.4 con razonamiento bajo para revisar prioridades, condiciones y propuestas secundarias. Las tarifas de referencia verificadas el 22/10/2026 son US$ 2,50 por millón de tokens de entrada y US$ 15 por millón de salida. Por ejemplo, 1.000 tokens de entrada y 500 de salida sumarían US$ 0,010. Es un escenario de cálculo, no una predicción de consumo. Consulta las [tarifas vigentes](https://developers.openai.com/api/docs/models/gpt-5.4). Cada mejora realiza dos solicitudes: reescritura y revisión editorial independiente, con el consumo de ambas etapas sumado. No hay reintentos automáticos ni cambios de modelo por detrás.

En **Ajustes › Datos y privacidad › Usar el texto de la ventana activa** puedes activar o desactivar el contexto de pantalla. Hablapp lee el texto que la aplicación expone mediante Accesibilidad para corregir grafías cercanas de nombres y términos. Las coincidencias ambiguas se conservan. No toma capturas, no usa OCR y no guarda ese contexto en el historial. Si una aplicación no expone su texto, esa referencia no estará disponible.

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

El audio siempre se transcribe en tu Mac. El formato habitual y los transforms locales usan Apple Intelligence. No hay analítica.

Si activas la mejora de prompts por API, el texto a transformar, las restricciones que se deben conservar y las instrucciones de ese transform se envían directamente a OpenAI con tu propia clave. No se envían audio, capturas, historial ni el texto completo de la ventana. Se solicita `store: false`; esto desactiva el almacenamiento de la respuesta para recuperación por API, pero no equivale a un acuerdo de retención cero. Se aplican las condiciones de datos de tu cuenta de OpenAI.

La app también se conecta a GitHub para consultar y descargar actualizaciones. Puedes desactivar la mejora por API o desconectar tu clave desde los ajustes en cualquier momento.

## Apoyar

hablapp es gratis y de código abierto. Puedes [apoyar el desarrollo en GitHub Sponsors](https://github.com/sponsors/briascoi) o [invitarme un cafecito](https://cafecito.app/briascoi). Tu aporte me ayuda a seguir creando software y a mantener Hablapp.

La app muestra un recordatorio discreto en la pantalla de dictado después de al menos siete días y veinte dictados. Puedes posponerlo treinta días, desactivarlo o indicar que ya apoyas el proyecto. No interrumpe el dictado ni bloquea funciones. El enlace para donar queda disponible en el menú, la barra lateral y **Ajustes › Acerca de**.

## Licencia

MIT. Ver [LICENSE](LICENSE).
