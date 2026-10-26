#!/bin/bash

set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

BASE="$HOME/Library/Application Support/VIDEOTV"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "======================================"
echo "        Instalando TVX"
echo "======================================"
echo

mkdir -p "$BASE"

# -----------------------------
# Comprobar FFmpeg (y Homebrew solo si hace falta)
# -----------------------------

if ! command -v ffmpeg >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "FFmpeg no está instalado y Homebrew tampoco."
        echo
        echo "Instala Homebrew desde:"
        echo "https://brew.sh"
        echo
        echo "Después vuelve a ejecutar este instalador."
        exit 1
    fi
    echo "FFmpeg no está instalado."
    echo "Instalándolo con Homebrew..."
    brew install ffmpeg
fi

# -----------------------------
# Copiar motor
# -----------------------------

echo "Instalando el motor de TVX..."

cp "$PROJECT_ROOT/src/VIDEOTV_Watcher.sh" \
   "$BASE/VIDEOTV_Watcher.sh"

cp "$PROJECT_ROOT/src/VIDEOTV_Processor.sh" \
   "$BASE/VIDEOTV_Processor.sh"

chmod +x "$BASE/VIDEOTV_Watcher.sh"
chmod +x "$BASE/VIDEOTV_Processor.sh"

cp "$PROJECT_ROOT/../Canva_Videos_Mac_PRO.command" \
   "$BASE/Canva_Videos_Mac_PRO.command"

cp "$PROJECT_ROOT/scripts/TVX_Siri.sh" "$BASE/TVX_Siri.sh"
cp "$PROJECT_ROOT/automation/TVX_Canva_Download.applescript" "$BASE/TVX_Canva_Download.applescript"
cp "$PROJECT_ROOT/automation/TVX_Canva_JS.sh" "$BASE/TVX_Canva_JS.sh"
chmod +x "$BASE/TVX_Siri.sh" "$BASE/TVX_Canva_JS.sh" "$BASE/Canva_Videos_Mac_PRO.command"

# Instalar integracion Apple Mail (desactivada por defecto).
MAIL_APPLESCRIPT="$PROJECT_ROOT/mail/VIDEOTV_Mail_corregido.applescript"
if [ ! -f "$MAIL_APPLESCRIPT" ]; then
    MAIL_APPLESCRIPT="$PROJECT_ROOT/mail/VIDEOTV_Mail.applescript"
fi
if [ ! -f "$MAIL_APPLESCRIPT" ]; then
    echo "No encuentro el AppleScript de Mail."
    echo "Busqué mail/VIDEOTV_Mail_corregido.applescript y mail/VIDEOTV_Mail.applescript."
    exit 1
fi

cp "$PROJECT_ROOT/mail/VIDEOTV_Mail.sh" "$BASE/VIDEOTV_Mail.sh"
cp "$MAIL_APPLESCRIPT" "$BASE/VIDEOTV_Mail.applescript"
chmod +x "$BASE/VIDEOTV_Mail.sh"
if [ ! -f "$BASE/mail_mode.txt" ]; then
    printf 'off\n' > "$BASE/mail_mode.txt"
fi
if [ ! -f "$BASE/mail_max_mb.txt" ]; then
    printf '5000\n' > "$BASE/mail_max_mb.txt"
fi

# -----------------------------
# Copiar interfaz
# -----------------------------

echo "Instalando la interfaz de progreso..."

if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "No encuentro el compilador de Swift."
    echo "Instala las Command Line Tools con: xcode-select --install"
    exit 1
fi

cp "$PROJECT_ROOT/ui/VIDEOTVProgress.swift" \
   "$BASE/VIDEOTVProgress.swift"

xcrun swiftc \
   "$BASE/VIDEOTVProgress.swift" \
   -o "$BASE/VIDEOTVProgress" \
   -framework AppKit

chmod +x "$BASE/VIDEOTVProgress"

# -----------------------------
# Copiar utilidad USB
# -----------------------------

if [ -f "$PROJECT_ROOT/scripts/Registrar_USB_VIDEOTV.command" ]; then
    cp "$PROJECT_ROOT/scripts/Registrar_USB_VIDEOTV.command" \
       "$BASE/Registrar_USB_VIDEOTV.command"
    chmod +x "$BASE/Registrar_USB_VIDEOTV.command"
else
    echo "No se incluyo Registrar_USB_VIDEOTV.command; se conserva el existente."
fi

# -----------------------------
# Copiar script de Automator
# -----------------------------

cp "$PROJECT_ROOT/automator/AUTOMATOR_SCRIPT.txt" \
   "$BASE/AUTOMATOR_SCRIPT.txt"

# Lo dejamos listo para pegar en Automator
if [ "${TVX_SKIP_PBCOPY:-0}" != "1" ]; then
    pbcopy < "$BASE/AUTOMATOR_SCRIPT.txt"
fi

# -----------------------------
# Archivos internos
# -----------------------------

touch "$BASE/usb_allowlist.txt"

# No borrar el lock si hay una descarga/procesamiento activo.
# El watcher es responsable de crear y limpiar este lock.

echo
echo "======================================"
echo "        TVX instalado ✅"
echo "======================================"
echo
echo "El script de Automator quedó copiado"
echo "en el portapapeles."
echo
echo "Ahora abre Automator y pégalo dentro"
echo "de la acción de carpeta de Descargas."
echo

echo "Apple Mail instalado. Modo actual: $(cat "$BASE/mail_mode.txt")"
echo "off = no se usa Mail; preview = prepara un borrador sin enviar;"
echo "send = intenta enviar de verdad (no recomendado con Gmail)."
echo "Puedes cambiarlo en: $BASE/mail_mode.txt"
echo "Límite de adjunto para Mail: $(cat "$BASE/mail_max_mb.txt") MB"
echo "Modo recomendado: preview (TVX prepara el borrador y tú lo envías)."
echo "Para borradores grandes, pon Borradores > En mi Mac en Ajustes > Cuentas."
echo
echo "Siri: crea un atajo llamado \"Descarga el Canva\" que ejecute:"
echo "$BASE/TVX_Siri.sh"
