#!/bin/bash
# TVX - Watcher robusto para exportaciones VIDEOTV de Canva
# Recibe desde Automator la RUTA EXACTA que acaba de entrar a Descargas.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

BASE="$HOME/Library/Application Support/VIDEOTV"
PROCESSOR="$BASE/VIDEOTV_Processor.sh"
LOCK="$BASE/.watcher_lock"
PENDING_DIR="$BASE/pending"
LOG="$BASE/watcher.log"

# Ruta absoluta del propio watcher, para poder reprogramar eventos en cola
# aunque el proceso se haya lanzado con una ruta relativa.
SELF="$0"
case "$SELF" in
  /*) ;;
  *) SELF="$(cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF")" ;;
esac

mkdir -p "$BASE" "$PENDING_DIR"
exec >> "$LOG" 2>&1

lock_age() {
  local mtime now
  mtime=$(stat -f '%m' "$LOCK" 2>/dev/null || echo 0)
  now=$(date +%s)
  echo $((now - ${mtime:-0}))
}

lock_is_active() {
  local pid cmd age
  pid=$(cat "$LOCK/pid" 2>/dev/null || true)

  if [ -n "$pid" ]; then
    kill -0 "$pid" 2>/dev/null || return 1
    cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if [ -z "$cmd" ]; then
      # No pudimos comprobar el comando; no arriesgamos quitar un lock vivo.
      return 0
    fi
    case "$cmd" in
      *VIDEOTV_Watcher.sh*) return 0 ;;
      *) return 1 ;;
    esac
  fi

  # Sin PID: dar un margen por si el lock se acaba de crear.
  age=$(lock_age)
  [ "$age" -lt 60 ]
}

queue_pending() {
  local tmp
  tmp="$PENDING_DIR/.tmp.$$.$RANDOM"
  printf '%s\n' "$1" > "$tmp" || return 1
  mv "$tmp" "$PENDING_DIR/$(date +%s).$$.$RANDOM.item"
}

drain_pending() {
  local item next
  item=$(find "$PENDING_DIR" -type f -name '*.item' -print -quit 2>/dev/null)
  [ -n "$item" ] || return 0
  next=$(cat "$item" 2>/dev/null || true)
  rm -f "$item"
  [ -n "$next" ] || return 0
  echo "Reprogramando evento pendiente: $next"
  nohup /bin/bash "$SELF" "$next" >/dev/null 2>&1 &
}

echo
echo "======================================"
echo "Evento detectado: $(date)"
echo "======================================"

if ! mkdir "$LOCK" 2>/dev/null; then
  if lock_is_active; then
    echo "Ya existe un procesamiento activo. Evento en cola: ${1:-}"
    if [ -n "${1:-}" ]; then
      queue_pending "$1" || echo "No pude guardar el evento en cola."
    fi
    exit 0
  fi

  echo "Lock viejo detectado; lo libero."
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || {
    echo "No pude tomar el lock después de limpiarlo."
    exit 1
  }
fi

printf '%s\n' "$$" > "$LOCK/pid"
trap 'rm -rf "$LOCK" 2>/dev/null || true; drain_pending' EXIT

valid_name() {
  local n="$1" lower
  lower=$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')

  # Archivos temporales de Safari/descargas: ignorar.
  case "$lower" in
    *.download|*.crdownload|*.part|*.tmp) return 1 ;;
  esac

  # El resultado final de TVX no se reprocesa.
  case "$lower" in
    videotv.mp4|video_tv.mp4) return 1 ;;
  esac

  # Exactos permitidos:
  # VIDEOTV / VIDEO_TV
  # VIDEOTV (2) / VIDEO_TV (2) / VIDEOTV 2 / VIDEO_TV 2
  # VIDEOTV.zip / VIDEO_TV.zip
  # VIDEOTV (2).zip / VIDEO_TV (2).zip / VIDEOTV 2.zip / VIDEO_TV 2.zip
  # VIDEOTV.zip(2) / VIDEO_TV.zip(2)
  [[ "$lower" =~ ^(videotv|video_tv)$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)[[:space:]]\([0-9]+\)$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)[[:space:]][0-9]+$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)\.zip$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)[[:space:]]\([0-9]+\)\.zip$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)[[:space:]][0-9]+\.zip$ ]] && return 0
  [[ "$lower" =~ ^(videotv|video_tv)\.zip[[:space:]]?\([0-9]+\)$ ]] && return 0

  # Exportaciones cuyo nombre incluye VIDEOTV en cualquier posición, por
  # ejemplo "Chamba — VIDEOTV.mp4". El contenido se valida después.
  case "$lower" in
    *videotv*|*video_tv*) return 0 ;;
  esac
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
  case "${CANDIDATE##*.}" in
    mp4|MP4|mov|MOV|m4v|M4V)
      echo "Video único; no hay ZIP que validar."
      ;;
    *)
      echo "Comprobando integridad del ZIP..."
      unzip -tq "$CANDIDATE" >/dev/null 2>&1 || {
        echo "ZIP incompleto o dañado."
        exit 1
      }

      # No usar grep -q dentro de un pipe con pipefail: grep cierra el pipe y
      # unzip puede terminar con SIGPIPE, haciendo que un ZIP válido parezca vacío.
      ZIP_LIST=$(mktemp "${TMPDIR:-/tmp/}tvx_zip.XXXXXX") || {
        echo "No pude crear un archivo temporal para leer el ZIP."
        exit 1
      }
      if ! unzip -Z1 "$CANDIDATE" > "$ZIP_LIST" 2>/dev/null; then
        rm -f "$ZIP_LIST"
        echo "No pude leer el contenido del ZIP."
        exit 1
      fi
      if ! grep -Eiq '\.(mp4|mov|m4v)$' "$ZIP_LIST"; then
        rm -f "$ZIP_LIST"
        echo "El ZIP no contiene videos compatibles. Ignorado."
        exit 0
      fi
      rm -f "$ZIP_LIST"
      ;;
  esac
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
