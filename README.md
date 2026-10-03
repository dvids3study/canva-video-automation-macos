# Canva Video Automation for macOS

A small automation project that started because of a very specific problem: Canva was exporting a TV project as multiple video files, and joining them manually every time was slow and repetitive.

The first version was a single macOS script. Over time, the project evolved into **TVX**, an automated workflow that can detect a Canva export, process the videos, verify the result and prepare the final file with almost no manual work.

---

# Automatización de videos de Canva para macOS

Este proyecto nació por un problema bastante específico: Canva exportaba un proyecto para TV como varios archivos de video y unirlos manualmente cada vez era lento y repetitivo.

La primera versión fue un único script para macOS. Con el tiempo, el proyecto evolucionó hasta convertirse en **TVX**, un flujo automatizado capaz de detectar una exportación de Canva, procesar los videos, verificar el resultado y preparar el archivo final casi sin intervención manual.

---

## How it started

The original version is:

```text
Canva_Videos_Mac_PRO.command
```

It was designed as a manual workflow. After downloading the Canva export, the script could find the latest `VIDEOTV` export, organize the clips, join them and create the final video.

This version is still included in the repository because it represents the first working version of the project.

### Features

- Detects Canva exports as ZIP files or extracted folders
- Supports names such as `VIDEOTV`, `VIDEOTV (2)` and `VIDEO_TV`
- Sorts clips in natural numeric order
- Preserves the original audio from each video
- Normalizes videos to 1920x1080 at 30 FPS
- Joins all clips using FFmpeg
- Verifies the final video before considering the process complete
- Saves the result as `VIDEOTV.mp4`
- Can automatically use an external USB drive
- Falls back to Downloads when no USB is available
- Safely moves processed source files to Trash
- Can eject the USB automatically after finishing

---

## Cómo empezó

La versión original es:

```text
Canva_Videos_Mac_PRO.command
```

Fue diseñada como un flujo manual. Después de descargar la exportación de Canva, el script podía encontrar la exportación `VIDEOTV` más reciente, organizar los clips, unirlos y crear el video final.

Esta versión todavía se conserva en el repositorio porque representa la primera versión funcional del proyecto.

### Funciones

- Detecta exportaciones de Canva como archivos ZIP o carpetas descomprimidas
- Reconoce nombres como `VIDEOTV`, `VIDEOTV (2)` y `VIDEO_TV`
- Ordena los clips de forma numérica natural
- Conserva el audio original de cada video
- Normaliza los videos a 1920x1080 y 30 FPS
- Une todos los clips usando FFmpeg
- Verifica el video final antes de considerar terminado el proceso
- Guarda el resultado como `VIDEOTV.mp4`
- Puede utilizar automáticamente una memoria USB externa
- Si no hay USB, guarda el resultado en Descargas
- Mueve de forma segura los archivos procesados a la Papelera
- Puede expulsar automáticamente la USB al terminar

---

# TVX

TVX is the next stage of the project.

Instead of manually running the processing script, TVX uses macOS automation to react when a new Canva export arrives in the Downloads folder.

The workflow currently looks like this:

```text
Canva
  ↓
VIDEOTV.zip
  ↓
Automator
  ↓
VIDEOTV Watcher
  ↓
FFmpeg processing
  ↓
Native progress window
  ↓
Video verification
  ↓
VIDEOTV.mp4
  ↓
USB or Downloads
```

TVX also includes a native macOS progress window that shows the current stage of the process and the video being processed.

---

# TVX

TVX es la siguiente etapa del proyecto.

En lugar de ejecutar manualmente el script de procesamiento, TVX utiliza automatización de macOS para reaccionar cuando llega una nueva exportación de Canva a la carpeta Descargas.

Actualmente el flujo funciona así:

```text
Canva
  ↓
VIDEOTV.zip
  ↓
Automator
  ↓
VIDEOTV Watcher
  ↓
Procesamiento con FFmpeg
  ↓
Ventana nativa de progreso
  ↓
Verificación del video
  ↓
VIDEOTV.mp4
  ↓
USB o Descargas
```

TVX también incluye una ventana de progreso nativa de macOS que muestra la etapa actual del proceso y el video que se está procesando.

---

## Project structure

```text
canva-video-automation-macos/
│
├── Canva_Videos_Mac_PRO.command
│
├── tvx/
│   ├── automator/
│   │   └── AUTOMATOR_SCRIPT.txt
│   │
│   ├── scripts/
│   │   ├── Instalar_TVX.command
│   │   └── Registrar_USB_VIDEOTV.command
│   │
│   ├── src/
│   │   ├── VIDEOTV_Processor.sh
│   │   └── VIDEOTV_Watcher.sh
│   │
│   └── ui/
│       └── VIDEOTVProgress.swift
│
├── .gitignore
└── README.md
```

---

## Estructura del proyecto

```text
canva-video-automation-macos/
│
├── Canva_Videos_Mac_PRO.command
│
├── tvx/
│   ├── automator/
│   │   └── AUTOMATOR_SCRIPT.txt
│   │
│   ├── scripts/
│   │   ├── Instalar_TVX.command
│   │   └── Registrar_USB_VIDEOTV.command
│   │
│   ├── src/
│   │   ├── VIDEOTV_Processor.sh
│   │   └── VIDEOTV_Watcher.sh
│   │
│   └── ui/
│       └── VIDEOTVProgress.swift
│
├── .gitignore
└── README.md
```

---

## Requirements

TVX currently runs on macOS and uses FFmpeg for video processing.

### Install Homebrew

If Homebrew is not installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple Silicon Macs:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Install FFmpeg

```bash
brew install ffmpeg
```

---

## Requisitos

TVX actualmente funciona en macOS y utiliza FFmpeg para procesar los videos.

### Instalar Homebrew

Si Homebrew todavía no está instalado:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

En Macs con Apple Silicon:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Instalar FFmpeg

```bash
brew install ffmpeg
```

---

## Installing TVX

From the repository, run:

```bash
chmod +x tvx/scripts/Instalar_TVX.command
./tvx/scripts/Instalar_TVX.command
```

The installer copies the required files into:

```text
~/Library/Application Support/VIDEOTV/
```

It also prepares the Automator script so it can be added to a macOS Folder Action watching the Downloads folder.

---

## Instalar TVX

Desde el repositorio ejecuta:

```bash
chmod +x tvx/scripts/Instalar_TVX.command
./tvx/scripts/Instalar_TVX.command
```

El instalador copia los archivos necesarios en:

```text
~/Library/Application Support/VIDEOTV/
```

También prepara el script de Automator para poder utilizarlo dentro de una Acción de carpeta de macOS que vigile Descargas.

---

## Current status

TVX is still evolving.

The current version already handles the full video-processing workflow, including automatic detection, progress feedback, verification and USB delivery.

Some ideas planned for future versions include Siri / Shortcuts integration and automatic email delivery.

---

## Estado actual

TVX todavía sigue evolucionando.

La versión actual ya se encarga de todo el flujo de procesamiento de video, incluyendo detección automática, progreso visual, verificación y entrega mediante USB.

Entre las próximas ideas están la integración con Siri / Atajos y el envío automático del video por correo.
