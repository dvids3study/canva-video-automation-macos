#!/bin/bash
# Canva_Videos_Mac_PRO.command
#
# Respaldo manual para cuando la descarga automática de Canva falla o se
# pausa. Toma el video/folder/ZIP de Canva que ya está en Descargas y lo
# procesa con el mismo popup (incluido el botón Detener), USB y correo.
#
# Uso normal: doble clic o Siri "pega el video del canva".
# También acepta una ruta como argumento:
#   Canva_Videos_Mac_PRO.command "/ruta/al/VIDEOTV"

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BASE="$HOME/Library/Application Support/VIDEOTV"
INSTALLED_PROCESSOR="$BASE/VIDEOTV_Processor.sh"
PROJECT_PROCESSOR="$PROJECT_DIR/tvx/src/VIDEOTV_Processor.sh"
DESCARGAS="$HOME/Downloads"

avisar() {
  osascript -e 'on run argv' \
    -e 'display alert "Canva Videos" message (item 1 of argv)' \
    -e 'end run' "$1" >/dev/null 2>&1 || true
}

if [ -x "$INSTALLED_PROCESSOR" ]; then
  PROCESSOR="$INSTALLED_PROCESSOR"
elif [ -x "$PROJECT_PROCESSOR" ]; then
  PROCESSOR="$PROJECT_PROCESSOR"
else
  avisar "No encontré el procesador de TVX. Ejecuta primero tvx/scripts/Instalar_TVX.command."
  exit 1
fi

ORIGEN=''

# 1) Ruta explícita (útil si Siri/Shortcuts recibe un archivo seleccionado).
if [ "$#" -gt 0 ] && [ -n "${1:-}" ] && [ -e "$1" ]; then
  ORIGEN="$1"
fi

# 2) Si no, buscar la descarga de Canva más reciente en Descargas.
if [ -z "$ORIGEN" ]; then
  [ -d "$DESCARGAS" ] || {
    avisar "No encuentro la carpeta de Descargas."
    exit 1
  }

  MEJOR=-1
  while IFS= read -r -d '' CANDIDATO; do
    NOMBRE=${CANDIDATO##*/}
    MINUS=$(printf '%s' "$NOMBRE" | tr '[:upper:]' '[:lower:]')

    case "$MINUS" in
      *videotv*|*video_tv*) ;;
      *) continue ;;
    esac

    # No reprocesar el video final ni archivos temporales de Safari.
    case "$MINUS" in
      videotv.mp4|*.download|*.crdownload|*.parcial|*.part|.*) continue ;;
    esac

    if [ -d "$CANDIDATO" ]; then
      find "$CANDIDATO" -type f \
        \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \) \
        -print -quit 2>/dev/null | grep -q . || continue
    elif [ -f "$CANDIDATO" ]; then
      case "$MINUS" in
        *.zip|*.mp4|*.mov|*.m4v) ;;
        *) continue ;;
      esac
      [ -s "$CANDIDATO" ] || continue
    else
      continue
    fi

    MTIME=$(stat -f '%m' "$CANDIDATO" 2>/dev/null || printf 0)
    [ "${MTIME:-0}" -gt "$MEJOR" ] && {
      MEJOR=$MTIME
      ORIGEN="$CANDIDATO"
    }
  done < <(find "$DESCARGAS" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print0 2>/dev/null)
fi

if [ -z "$ORIGEN" ] || [ ! -e "$ORIGEN" ]; then
  avisar "No encontré un video de Canva en Descargas. Descarga primero el diseño o pasa la ruta como argumento."
  exit 0
fi

# Prueba de integración: verifica la ruta sin procesar nada.
if [ "${1:-}" = "--check" ]; then
  printf 'OK: %s\n' "$ORIGEN"
  exit 0
fi

if [ "${TVX_DRY_RUN:-0}" = "1" ]; then
  printf '%s\n' "$ORIGEN"
  exit 0
fi

echo "Canva Videos: procesando ${ORIGEN##*/}"
exec "$PROCESSOR" "$ORIGEN"
