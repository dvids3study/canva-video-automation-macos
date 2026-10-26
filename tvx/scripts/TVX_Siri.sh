#!/bin/bash
# TVX - flujo por voz desde Siri / Atajos.
#
# Uso normal (lo que ejecuta el atajo "Descarga el Canva"):
#   TVX_Siri.sh
# Abre Canva, intenta iniciar la descarga y deja un proceso esperando el archivo.
#
# Modo interno:
#   TVX_Siri.sh --watch
#   TVX_Siri.sh --inspect   (lista los elementos de Canva; requiere Accesibilidad)

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

BASE="$HOME/Library/Application Support/VIDEOTV"
DESCARGAS="${TVX_DOWNLOADS:-$HOME/Downloads}"
WATCHER="$BASE/VIDEOTV_Watcher.sh"
CANVA_SCRIPT="$BASE/TVX_Canva_Download.applescript"
CANVA_JS="$BASE/TVX_Canva_JS.sh"
STATUS="$BASE/status.tsv"
LAST_SUCCESS="$BASE/last_success.tsv"
LOG="$BASE/siri.log"
LOCK="$BASE/.siri_watch_lock"
URL_FILE="$BASE/canva_url.txt"
TIMEOUT="${TVX_SIRI_TIMEOUT:-1200}"

SELF="$0"
case "$SELF" in
  /*) ;;
  *) SELF="$(cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF")" ;;
esac

mkdir -p "$BASE"
exec >> "$LOG" 2>&1

notify() {
  osascript -e 'on run argv' \
    -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
    -e 'end run' "$1" "$2" >/dev/null 2>&1 || true
}

canva_url() {
  [ -f "$URL_FILE" ] && head -n 1 "$URL_FILE" | tr -d '\r'
}

open_canva() {
  local url
  url=$(canva_url)
  if [ -n "$url" ]; then
    open -a Safari "$url" >/dev/null 2>&1 || true
  else
    if osascript -e 'tell application "System Events" to tell process "Safari" to get name of every window' 2>/dev/null | grep -qi canva; then
      osascript -e 'tell application "Safari"
        repeat with w in windows
          if name of w contains "Canva" then
            set index of w to 1
            exit repeat
          end if
        end repeat
        activate
      end tell' >/dev/null 2>&1 || true
    else
      open -a Safari "https://www.canva.com/" >/dev/null 2>&1 || true
    fi
  fi
  sleep 5
  osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
}

try_download() {
  local result
  if [ ! -f "$CANVA_SCRIPT" ] && [ ! -x "$CANVA_JS" ]; then
    echo "Falta $CANVA_SCRIPT"
    return 1
  fi

  # Primero, JavaScript sobre la página de Canva (más fiable que el árbol AX).
  if [ "${TVX_CANVA_JS:-1}" = "1" ] && [ -x "$CANVA_JS" ]; then
    result=$("$CANVA_JS" 2>&1)
    echo "Canva JS: $result"
    case "$result" in
      CLICKED*)
        notify "TVX" "Descarga iniciada en Canva web. TVX espera el archivo."
        return 0
        ;;
    esac
  fi

  local attempt result
  for attempt in 1 2 3; do
    result=$(osascript "$CANVA_SCRIPT" download "Safari" 2>&1)
    echo "Canva download intento $attempt: $result"
    case "$result" in
      CLICKED*|NO_PERMISSION*|MANUAL*|NO_BUTTON*|DIALOG_FAILED*) break ;;
    esac
    sleep 3
  done
  case "$result" in
    CLICKED*)
      notify "TVX" "Descarga iniciada en Canva web. TVX espera el archivo."
      return 0
      ;;
    NO_CANVA*)
      notify "TVX" "No encontré Canva en Safari. Abre el diseño y pulsa Descargar."
      ;;
    NO_WINDOW*)
      notify "TVX" "Abre el diseño en Canva web (Safari). TVX espera la descarga."
      ;;
    NO_PERMISSION*)
      notify "TVX" "Activa Accesibilidad para Atajos. Mientras, pulsa Descargar en Canva web."
      ;;
    MANUAL*|NO_BUTTON*|DIALOG_FAILED*)
      notify "TVX" "No pude pulsar Descargar por ti. Pulsa tú en Canva web; TVX espera."
      ;;
    *)
      notify "TVX" "No pude iniciar la descarga. Pulsa Descargar en Canva; TVX espera."
      ;;
  esac
  return 1
}

if [ "${1:-}" = "--inspect" ]; then
  echo "=== $(date) inspección de Canva ==="
  if [ -f "$CANVA_SCRIPT" ]; then
    osascript "$CANVA_SCRIPT" inspect "Safari" 2>&1
  else
    echo "Falta $CANVA_SCRIPT"
  fi
  exit 0
fi

if [ "${1:-}" != "--watch" ]; then
  echo "=== $(date) Siri: inicio ==="

  if [ -d "$LOCK" ]; then
    OLD_PID=$(cat "$LOCK/pid" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "Ya hay una espera de Siri activa (pid $OLD_PID)."
      notify "TVX" "Ya estoy esperando una descarga de Canva."
      exit 0
    fi
  fi

  if [ ! -d "/Applications/Safari.app" ]; then
    notify "TVX" "No encontré Safari. Instálalo o configura canva_url.txt."
    exit 1
  fi

  FREE_KB=$(df -Pk "$DESCARGAS" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ "${FREE_KB:-0}" -lt 2097152 ]; then
    notify "TVX" "Queda poco espacio en Descargas. Libera espacio antes de exportar."
  fi

  if [ "${TVX_SIRI_NO_OPEN:-0}" != "1" ]; then
    open_canva
  fi

  # La espera debe empezar antes de lanzar la descarga para no perder el archivo.
  nohup /bin/bash "$SELF" --watch >/dev/null 2>&1 &
  sleep 1

  if [ "${TVX_CANVA_AUTOCLICK:-1}" != "0" ]; then
    try_download
  else
    notify "TVX" "Pulsa Descargar en Canva. TVX espera la exportación."
  fi
  exit 0
fi

# --- Modo espera -----------------------------------------------------------
if ! mkdir "$LOCK" 2>/dev/null; then
  OLD_PID=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Ya hay una espera de Siri activa (pid $OLD_PID)."
    notify "TVX" "Ya estoy esperando una descarga de Canva."
    exit 0
  fi
  echo "Lock viejo de Siri; lo libero."
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" > "$LOCK/pid"
trap 'rm -rf "$LOCK" 2>/dev/null || true' EXIT

echo "=== $(date) esperando exportación en $DESCARGAS ==="
START=$(date +%s)
START_DATE=$(date -r "$START" '+%Y-%m-%d %H:%M:%S')
CANDIDATE=""

while [ $(( $(date +%s) - START )) -lt "$TIMEOUT" ]; do
  # Si la Acción de carpeta u otra vía ya procesó la exportación, no duplicar.
  if [ -f "$STATUS" ]; then
    STATE_MTIME=$(stat -f '%m' "$STATUS" 2>/dev/null || echo 0)
    if [ "$STATE_MTIME" -ge "$START" ]; then
      STATE=$(cut -f1 "$STATUS" 2>/dev/null || true)
      case "$STATE" in
        success|preview|error)
          echo "Otra vía ya procesó la exportación (estado: $STATE)."
          exit 0
          ;;
      esac
    fi
  fi
  if [ -f "$LAST_SUCCESS" ]; then
    LAST_TS=$(awk -F '\t' '{print $2}' "$LAST_SUCCESS" 2>/dev/null || true)
    if [ -n "$LAST_TS" ] && [ "$LAST_TS" -ge "$START" ] 2>/dev/null; then
      echo "Otra vía ya procesó la exportación (last_success)."
      exit 0
    fi
  fi

  CANDIDATE=$(find "$DESCARGAS" -maxdepth 1 \
    \( -type f -o -type d \) \
    \( -iname '*videotv*.zip' -o -iname '*video_tv*.zip' \
       -o -iname '*videotv*.mp4' -o -iname '*video_tv*.mp4' \
       -o -iname '*videotv*' -o -iname '*video_tv*' \) \
    ! -name '*.parcial' ! -iname '*.download' ! -iname '*.crdownload' \
    ! -iname '*.part' ! -iname '*.tmp' \
    ! -iname 'VIDEOTV.mp4' ! -iname 'VIDEO_TV.mp4' \
    -newermt "$START_DATE" -print -quit 2>/dev/null)
  [ -n "$CANDIDATE" ] && break

  sleep 3
done

if [ -z "$CANDIDATE" ]; then
  echo "No apareció ninguna exportación en ${TIMEOUT}s."
  notify "TVX" "No vi la descarga de Canva. Abre Canva y pulsa Descargar."
  exit 0
fi

echo "Exportación detectada: $CANDIDATE"
notify "TVX" "Descarga detectada. Procesando..."
if [ -x "$WATCHER" ]; then
  "$WATCHER" "$CANDIDATE"
  RC=$?
  echo "Watcher terminó con código $RC."
  if [ "$RC" -ne 0 ]; then
    notify "TVX" "No se pudo procesar la exportación. Revisa siri.log."
  fi
else
  echo "Falta el Watcher: $WATCHER"
  notify "TVX" "TVX no está instalado: falta VIDEOTV_Watcher.sh."
fi
exit 0
