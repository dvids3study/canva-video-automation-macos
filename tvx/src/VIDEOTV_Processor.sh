#!/bin/bash
# TVX - Procesador VIDEOTV
# IMPORTANTE: procesa únicamente la ruta exacta entregada por el watcher.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

BASE="$HOME/Library/Application Support/VIDEOTV"
DESCARGAS="$HOME/Downloads"
STATUS="$BASE/status.tsv"
GUI="$BASE/VIDEOTVProgress"
USB_ALLOWLIST="$BASE/usb_allowlist.txt"
LAST_SUCCESS="$BASE/last_success.tsv"
LOG="$BASE/processor.log"

mkdir -p "$BASE"
touch "$USB_ALLOWLIST" "$LOG"
exec >> "$LOG" 2>&1

clean_field(){ printf '%s' "$1" | tr '\t\r\n' '   '; }

status_write(){
  local tmp="$STATUS.tmp.$$"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(clean_field "$1")" \
    "$(clean_field "$2")" \
    "$(clean_field "${3:-}")" \
    "${4:-0}" "${5:-0}" \
    "$(clean_field "${6:-}")" > "$tmp"
  mv -f "$tmp" "$STATUS"
}

notify(){
  osascript -e 'on run argv' \
    -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
    -e 'end run' "$1" "$2" >/dev/null 2>&1 || true
}

launch_gui(){
  [ -x "$GUI" ] && "$GUI" "$STATUS" >/dev/null 2>&1 &
}

fail(){
  local msg="$1"
  echo "ERROR: $msg" >&2
  status_write error Error "$msg" 100 0 ""
  notify "VIDEOTV" "$msg"
  exit 1
}

verify_video(){
  local f="$1" d
  [ -s "$f" ] || return 1

  ffprobe -v error -select_streams v:0 \
    -show_entries stream=index -of csv=p=0 "$f" 2>/dev/null | grep -q . || return 1

  ffprobe -v error -select_streams a:0 \
    -show_entries stream=index -of csv=p=0 "$f" 2>/dev/null | grep -q . || return 1

  d=$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || true)

  awk -v d="$d" 'BEGIN{exit !((d+0)>0)}'
}

move_to_trash(){
  local item="$1" trash="$HOME/.Trash" name target n=2
  [ -e "$item" ] || return 0
  mkdir -p "$trash" || return 1
  name=${item##*/}
  target="$trash/$name"

  while [ -e "$target" ]; do
    target="$trash/${name} ($n)"
    n=$((n+1))
  done

  mv "$item" "$target"
}

register_success(){
  printf '%s\t%s\t%s\n' "$1" "$(date +%s)" "$2" > "$LAST_SUCCESS"
}

is_recent_duplicate(){
  [ -f "$LAST_SUCCESS" ] || return 1
  local h t o now age
  IFS=$'\t' read -r h t o < "$LAST_SUCCESS" || return 1
  [ "$h" = "$1" ] || return 1
  now=$(date +%s)
  age=$((now-${t:-0}))
  [ "$age" -ge 0 ] && [ "$age" -le 600 ]
}

for c in ffmpeg ffprobe shasum diskutil plutil perl; do
  command -v "$c" >/dev/null 2>&1 || fail "No encuentro $c."
done

ORIGEN="${1:-}"
[ -n "$ORIGEN" ] || fail "No recibí la descarga de Canva."
[ -e "$ORIGEN" ] || fail "La descarga indicada ya no existe."

status_write processing "Preparando VIDEOTV" "${ORIGEN##*/}" 3 0 ""
launch_gui

WORK=$(mktemp -d "${TMPDIR:-/tmp/}tvx.XXXXXXXX") || fail "No pude crear la carpeta temporal."
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/source" "$WORK/clips"

if [ -f "$ORIGEN" ]; then
  status_write processing "Comprobando ZIP" "Validando la descarga" 8 0 ""
  unzip -tq "$ORIGEN" >/dev/null 2>&1 || fail "VIDEOTV.zip está incompleto o dañado."

  status_write processing "Extrayendo videos" "Preparando los archivos" 12 0 ""
  ditto -x -k "$ORIGEN" "$WORK/source" || fail "No pude extraer VIDEOTV.zip."
  SOURCE="$WORK/source"
else
  SOURCE="$ORIGEN"
fi

# Crear lista de videos y ordenarla naturalmente.
# Los nombres exportados por Canva no contienen saltos de línea.
RAW_LIST="$WORK/videos_raw.txt"
SORTED_LIST="$WORK/videos_sorted.txt"

find "$SOURCE" -type f \
  \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \) \
  ! -path '*/__MACOSX/*' ! -name '._*' \
  -print > "$RAW_LIST"

[ -s "$RAW_LIST" ] || fail "La descarga no contiene videos MP4, MOV o M4V."

perl -e '
  chomp(@x = <>);
  sub key {
    my $s = lc(shift);
    $s =~ s/(\d+)/sprintf("%020d",$1)/ge;
    return $s;
  }
  print "$_\n" for sort { key($a) cmp key($b) } @x;
' "$RAW_LIST" > "$SORTED_LIST"

TOTAL=$(wc -l < "$SORTED_LIST" | tr -d ' ')
[ "${TOTAL:-0}" -gt 0 ] || fail "No pude identificar los videos de la descarga."

status_write processing "Analizando contenido" "$TOTAL videos encontrados" 15 0 ""

# Hash real del contenido para detectar duplicados recientes.
HASH_INPUT="$WORK/hashes.txt"
: > "$HASH_INPUT"
while IFS= read -r f; do
  shasum -a 256 "$f" | awk '{print $1}' >> "$HASH_INPUT"
done < "$SORTED_LIST"

CONTENT_HASH=$(shasum -a 256 "$HASH_INPUT" | awk '{print $1}')

if is_recent_duplicate "$CONTENT_HASH"; then
  status_write success "VIDEOTV ya procesado" "Descarga duplicada; no se volvió a procesar" 100 0 ""
  move_to_trash "$ORIGEN" || true
  notify "VIDEOTV" "La descarga era un duplicado reciente."
  sleep 4
  exit 0
fi

CONCAT_LIST="$WORK/concat.txt"
: > "$CONCAT_LIST"
COUNT=0
START_ALL=$(date +%s)

while IFS= read -r VIDEO; do
  COUNT=$((COUNT+1))
  CLIP=$(printf '%s/clips/clip_%05d.mp4' "$WORK" "$COUNT")
  PCT=$((20 + COUNT * 60 / TOTAL))

  NOW=$(date +%s)
  ELAPSED=$((NOW - START_ALL))
  ETA=0
  if [ "$COUNT" -gt 1 ]; then
    AVG=$((ELAPSED / (COUNT - 1)))
    ETA=$((AVG * (TOTAL - COUNT + 1) + 15))
  fi

  status_write processing "Procesando videos" "Video $COUNT de $TOTAL" "$PCT" "$ETA" ""

  HAS_AUDIO=0
  if ffprobe -v error -select_streams a:0 \
      -show_entries stream=index -of csv=p=0 "$VIDEO" 2>/dev/null | grep -q .; then
    HAS_AUDIO=1
  fi

  if [ "$HAS_AUDIO" -eq 1 ]; then
    ffmpeg -hide_banner -loglevel error -nostdin -y \
      -i "$VIDEO" \
      -map 0:v:0 -map 0:a:0 \
      -vf 'fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p' \
      -af 'aresample=48000:async=1:first_pts=0' \
      -c:v libx264 -preset fast -crf 20 -r 30 -pix_fmt yuv420p \
      -c:a aac -b:a 192k -ar 48000 -ac 2 \
      "$CLIP" || fail "No se pudo procesar el video $COUNT de $TOTAL."
  else
    ffmpeg -hide_banner -loglevel error -nostdin -y \
      -i "$VIDEO" \
      -f lavfi -i 'anullsrc=channel_layout=stereo:sample_rate=48000' \
      -map 0:v:0 -map 1:a:0 \
      -vf 'fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p' \
      -c:v libx264 -preset fast -crf 20 -r 30 -pix_fmt yuv420p \
      -c:a aac -b:a 192k -ar 48000 -ac 2 \
      -shortest "$CLIP" || fail "No se pudo procesar el video $COUNT de $TOTAL."
  fi

  printf "file '%s'\n" "$CLIP" >> "$CONCAT_LIST"
done < "$SORTED_LIST"

FINAL_TEMP="$WORK/VIDEOTV.mp4"

status_write processing "Uniendo videos" "$TOTAL videos preparados" 84 10 ""
ffmpeg -hide_banner -loglevel error -nostdin -y \
  -f concat -safe 0 -i "$CONCAT_LIST" \
  -c copy -movflags +faststart "$FINAL_TEMP" || fail "No se pudieron unir los videos."

status_write processing "Verificando video" "Comprobando video, audio y duración" 89 6 ""
verify_video "$FINAL_TEMP" || fail "El video final no pasó la verificación de integridad."

status_write processing "Buscando destino" "Comprobando USB y Descargas" 92 4 ""

ALLOWLIST_ACTIVE=0
if grep -Ev '^[[:space:]]*(#|$)' "$USB_ALLOWLIST" 2>/dev/null | grep -q .; then
  ALLOWLIST_ACTIVE=1
fi

USB_COUNT=0
USB_DEST=""
USB_NAME=""

for VOLUME in /Volumes/*; do
  [ -d "$VOLUME" ] || continue
  INFO=$(diskutil info -plist "$VOLUME" 2>/dev/null) || continue

  BUS=$(printf '%s' "$INFO" | plutil -extract BusProtocol raw -o - - 2>/dev/null || true)
  INTERNAL=$(printf '%s' "$INFO" | plutil -extract Internal raw -o - - 2>/dev/null || true)
  READONLY=$(printf '%s' "$INFO" | plutil -extract ReadOnlyVolume raw -o - - 2>/dev/null || true)
  UUID=$(printf '%s' "$INFO" | plutil -extract VolumeUUID raw -o - - 2>/dev/null || true)

  [ "$BUS" = "USB" ] || continue
  [ "$INTERNAL" != "true" ] || continue
  [ "$READONLY" != "true" ] || continue
  [ -w "$VOLUME" ] || continue

  if [ "$ALLOWLIST_ACTIVE" -eq 1 ]; then
    [ -n "$UUID" ] || continue
    grep -Fxq "$UUID" "$USB_ALLOWLIST" || continue
  fi

  USB_COUNT=$((USB_COUNT+1))
  USB_DEST="$VOLUME"
  USB_NAME=${VOLUME##*/}
done

if [ "$USB_COUNT" -eq 1 ]; then
  DEST="$USB_DEST"
  DEST_KIND="usb"
  status_write processing "Copiando a USB" "$USB_NAME" 94 0 ""
else
  DEST="$DESCARGAS"
  DEST_KIND="downloads"
  status_write processing "Guardando en Descargas" "VIDEOTV.mp4" 94 0 ""
fi

FINAL_PATH="$DEST/VIDEOTV.mp4"
PARTIAL="$FINAL_PATH.parcial"
rm -f "$PARTIAL" 2>/dev/null || true

if ! cp "$FINAL_TEMP" "$PARTIAL"; then
  if [ "$DEST_KIND" = "usb" ]; then
    DEST="$DESCARGAS"
    DEST_KIND="downloads"
    FINAL_PATH="$DEST/VIDEOTV.mp4"
    PARTIAL="$FINAL_PATH.parcial"
    rm -f "$PARTIAL" 2>/dev/null || true
    status_write processing "USB no disponible" "Guardando una copia segura en Descargas" 95 0 ""
    cp "$FINAL_TEMP" "$PARTIAL" || fail "No se pudo guardar ni en la USB ni en Descargas."
  else
    fail "No se pudo guardar VIDEOTV.mp4 en Descargas."
  fi
fi

sync
verify_video "$PARTIAL" || {
  rm -f "$PARTIAL" 2>/dev/null || true
  fail "La copia final no pasó la verificación."
}

mv -f "$PARTIAL" "$FINAL_PATH" || fail "No se pudo finalizar VIDEOTV.mp4."
sync
verify_video "$FINAL_PATH" || fail "VIDEOTV.mp4 no pasó la verificación final."

register_success "$CONTENT_HASH" "$FINAL_PATH"

# Limpieza estricta: SOLO la entrada exacta usada.
status_write processing "Limpiando descarga" "Moviendo la fuente utilizada a la Papelera" 98 0 ""
move_to_trash "$ORIGEN" || true

EJECTED=0
if [ "$DEST_KIND" = "usb" ]; then
  status_write processing "Expulsando USB" "$USB_NAME" 99 0 ""
  sync
  sleep 1
  if diskutil eject "$USB_DEST" >/dev/null 2>&1; then
    EJECTED=1
  fi
fi

if [ "$DEST_KIND" = "usb" ]; then
  if [ "$EJECTED" -eq 1 ]; then
    status_write success "VIDEOTV listo" "Guardado en USB · Memoria expulsada" 100 0 "$USB_NAME"
    notify "VIDEOTV listo" "Guardado en USB. Ya puedes retirar la memoria."
  else
    status_write success "VIDEOTV listo" "Guardado en USB · Expúlsala desde Finder" 100 0 "$USB_NAME"
    notify "VIDEOTV listo" "Guardado en USB. Expúlsala desde Finder antes de retirarla."
  fi
else
  status_write success "VIDEOTV listo" "Guardado en Descargas" 100 0 "$FINAL_PATH"
  notify "VIDEOTV listo" "VIDEOTV.mp4 quedó guardado en Descargas."
fi

sleep 4
exit 0
