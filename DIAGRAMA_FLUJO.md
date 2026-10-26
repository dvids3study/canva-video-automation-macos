# Diagrama de flujo · VIDEOTV

![Diagrama de flujo de VIDEOTV](DIAGRAMA_FLUJO.png)

También está disponible en:

- [`DIAGRAMA_FLUJO.png`](DIAGRAMA_FLUJO.png) — para pantalla o documentación.
- [`DIAGRAMA_FLUJO.pdf`](DIAGRAMA_FLUJO.pdf) — para imprimir o compartir.

## Flujo resumido

```mermaid
flowchart TD
    A["Siri: Descarga el Canva"] --> B["Atajo de macOS"]
    C["Siri: Pega el video del canva"] --> D["Atajo de macOS"]
    E["Folder Action / Automator"] --> F["VIDEOTV_Watcher.sh"]

    B --> G["TVX_Siri.sh"]
    G --> H["Safari + AppleScript/JXA"]
    H --> I["Canva Web: Compartir → Descargar MP4"]
    I --> J["~/Downloads/VIDEOTV*"]
    J --> F

    D --> K["Canva_Videos_Mac_PRO.command"]
    K --> L["VIDEOTV_Processor.sh"]
    F --> L

    L --> M["VIDEOTVProgress + status.tsv"]
    L --> N["Extrae ZIP y ordena los clips"]
    N --> O["FFmpeg: normaliza cada clip"]
    O --> P["FFmpeg: concat"]
    P --> Q["ffprobe: verifica video, audio y duración"]

    Q --> R{"¿Hay una sola USB escribible?"}
    R -->|sí| S["Copia a USB + expulsa"]
    R -->|no| T["~/Downloads/VIDEOTV.mp4"]
    T --> U["Apple Mail: envía o deja borrador"]
    S --> V["Notifica, mueve la fuente a Papelera y registra el hash"]
    U --> V

    M -.->|Detener| W["Confirmación del usuario"]
    W --> X["Cancela FFmpeg y Processor"]
    Q -->|falla| Y["Error en el popup; la fuente queda intacta"]
```

## Herramientas utilizadas

| Capa | Herramientas | Para qué |
|---|---|---|
| Activación | macOS, Siri, Atajos, Finder, Automator | Lanzar el flujo por voz o por Acción de carpeta. |
| Descarga | Safari, AppleScript, JavaScript for Automation | Abrir Canva y pulsar Compartir → Descargar. |
| Detección | Bash, `stat`, `shasum`, `unzip` | Esperar a que el archivo esté estable y validar que no sea un duplicado. |
| Procesamiento | Bash, `ditto`, `awk`, `sort` | Extraer, ordenar y preparar los clips. |
| Video | FFmpeg, ffprobe | Normalizar, unir y verificar el MP4 final. |
| Interfaz | Swift, AppKit, `NSVisualEffectView`, `NSAlert` | Popup de vidrio, progreso, ETA, confirmación y botón Detener. |
| Entrega | Apple Mail, AppleScript | Enviar el video o dejar un borrador para revisión. |
| Almacenamiento | `diskutil`, `plutil`, `cp`, `sync` | Detectar la USB, copiar y expulsarla de forma segura. |
| Avisos | `osascript` | Notificaciones del sistema. |

## Dónde queda cada cosa

| Ruta | Contenido |
|---|---|
| `~/Documents/Canva_Videos_Mac_PRO/` | Proyecto, comando de respaldo, este diagrama y el código fuente. |
| `~/Library/Application Support/VIDEOTV/` | Runtime instalado: scripts, UI, `status.tsv`, `processor.pid`, `mail_mode.txt` y logs. |
| `~/Downloads/VIDEOTV.mp4` | Video final cuando no hay una USB disponible. |
| `/Volumes/<nombre>/VIDEOTV.mp4` | Video final cuando hay una sola USB escribible. |

## Notas

- **Detener** cancela el procesamiento; no guarda el video final ni envía correo.
- Un **error de procesamiento** deja la fuente intacta y muestra el motivo en el popup.
- El **respaldo** `Canva_Videos_Mac_PRO.command` procesa una descarga que ya está en `~/Downloads`; es útil si la descarga automática falla o se pausa.
