#!/bin/bash
# TVX - Watcher robusto para exportaciones VIDEOTV de Canva
# Recibe desde Automator la RUTA EXACTA que acaba de entrar a Descargas.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

BASE="$HOME/Library/Application Support/VIDEOTV"
PROCESSOR="$BASE/VIDEOTV_Processor.sh"
LOCK="$BASE/.watcher_lock"
LOG="$BASE/watcher.log"

mkdir -p "$BASE"
exec >> "$LOG" 2>&1

echo
echo "======================================"
echo "Evento detectado: $(date)"
echo "======================================"

if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Ya existe un procesamiento activo. Evento ignorado."
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

valid_name() {
  local n="$1" lower
  lower=$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')

  # Exactos permitidos:
  # VIDEOTV / VIDEO_TV
  # VIDEOTV (2) / VIDEO_TV (2)
  # VIDEOTV.zip / VIDEO_TV.zip
  # VIDEOTV (2).zip / VIDEO_TV (2).zip
  # VIDEOTV.zip(2) / VIDEO_TV.zip(2)
  [[ "$lower" =~ ^(videotv|video_tv)$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)[[:space:]]\([0-9]+\)$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)\.zip$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)[[:space:]]\([0-9]+\)\.zip$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)\.zip[[:space:]]?\([0-9]+\)$ ]] && return 0
  return 1
}

snapshot() {
  local p="$1"

  if [ -d "$p" ]; then
    find "$p" -type f -exec stat -f '%m:%z:%N' {} + 2>/dev/null \
      | sort | shasum | awk '{print $1}'
  else
    stat -f '%m:%z' "$p" 2>/dev/null
  fi
}

CANDIDATE="${1:-}"

if [ -z "$CANDIDATE" ]; then
  echo "Automator no envió una ruta. No se procesará nada."
  exit 0
fi

NAME=${CANDIDATE##*/}
valid_name "$NAME" || {
  echo "Ignorado por nombre: $NAME"
  exit 0
}

# Automator puede disparar antes de que Finder/Canva termine de crear el nombre final.
for _ in $(seq 1 90); do
  [ -e "$CANDIDATE" ] && break
  sleep 2
done

[ -e "$CANDIDATE" ] || {
  echo "La descarga no apareció: $CANDIDATE"
  exit 0
}

echo "Fuente exacta: $CANDIDATE"
echo "Esperando a que termine de escribirse..."

PREV=""
STABLE=0

# Hasta ~12 minutos, útil para ZIP grandes o conexiones lentas.
for _ in $(seq 1 180); do
  [ -e "$CANDIDATE" ] || {
    echo "La descarga desapareció mientras esperaba."
    exit 0
  }

  CUR=$(snapshot "$CANDIDATE")

  if [ -n "$CUR" ] && [ "$CUR" = "$PREV" ]; then
    STABLE=$((STABLE + 1))
    echo "Descarga estable: $STABLE/3"
  else
    STABLE=0
    echo "Canva todavía está escribiendo..."
  fi

  PREV="$CUR"
  [ "$STABLE" -ge 3 ] && break
  sleep 4
done

[ "$STABLE" -ge 3 ] || {
  echo "La descarga no se estabilizó."
  exit 1
}

# Validar contenido DESPUÉS de que ya esté estable.
if [ -f "$CANDIDATE" ]; then
  echo "Comprobando integridad del ZIP..."
  unzip -tq "$CANDIDATE" >/dev/null 2>&1 || {
    echo "ZIP incompleto o dañado."
    exit 1
  }

  unzip -Z1 "$CANDIDATE" 2>/dev/null | grep -Eiq '\.(mp4|mov|m4v)$' || {
    echo "El ZIP no contiene videos compatibles. Ignorado."
    exit 0
  }
else
  find "$CANDIDATE" -type f \
    \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \) \
    -print -quit 2>/dev/null | grep -q . || {
      echo "La carpeta no contiene videos compatibles. Ignorada."
      exit 0
    }
fi

echo "Descarga válida. Iniciando procesador..."
"$PROCESSOR" "$CANDIDATE"
RC=$?

echo "Procesador finalizó con código $RC."
exit "$RC"
