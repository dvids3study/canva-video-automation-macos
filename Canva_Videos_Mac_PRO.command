#!/bin/bash
# Canva TV -> video final (macOS / Bash 3.2)
#
# Qué hace este script, paso a paso:
#
#  1) Busca en Descargas lo último que hayas bajado de Canva:
#       VIDEOTV, VIDEOTV (2), VIDEO_TV... o sus versiones en ZIP.
#  2) Si Safari ya descomprimió el ZIP, usa la carpeta tal cual.
#  3) Ordena los videos como lo haría una persona: 1, 2, 3 ... 10, 11
#     (no 1, 10, 11, 2).
#  4) Respeta la música/audio que ya viene dentro de cada MP4.
#  5) Junta todos los clips en un solo video.
#  6) Revisa que el resultado tenga imagen, sonido y una duración real.
#  7) Si hay una única USB conectada y se puede escribir en ella, lo guarda ahí.
#     Si no hay ninguna (o hay varias), lo deja en Descargas.
#  8) Cuando comprueba que la copia quedó bien, manda las descargas
#     VIDEOTV a la Papelera.
#  9) Si lo guardó en la USB, la expulsa por ti de forma segura.
#
# Necesitas ffmpeg y ffprobe instalados con Homebrew.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Muestra un aviso en pantalla (si algo falla con el aviso, no pasa nada).
avisar() {
  osascript -e 'on run argv' \
    -e 'display alert "Videos de Canva" message (item 1 of argv)' \
    -e 'end run' "$1" >/dev/null 2>&1 || true
}

# Algo salió mal: lo contamos con calma, avisamos y salimos.
fallar() {
  printf '\nUps, algo salió mal: %s\n' "$*" >&2
  avisar "$*"
  read -r -p 'Pulsa Enter para cerrar... ' _ || true
  exit 1
}

# Comprueba que un video esté sano: que exista, que no esté vacío,
# que tenga imagen, sonido y una duración mayor que cero.
verificar_video() {
  local archivo="$1"
  [ -f "$archivo" ] || return 1
  [ -s "$archivo" ] || return 1

  ffprobe -v error -select_streams v:0 \
    -show_entries stream=index -of csv=p=0 "$archivo" 2>/dev/null | grep -q . || return 1

  ffprobe -v error -select_streams a:0 \
    -show_entries stream=index -of csv=p=0 "$archivo" 2>/dev/null | grep -q . || return 1

  local duracion
  duracion=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$archivo" 2>/dev/null || true)

  awk -v d="$duracion" 'BEGIN { exit !((d + 0) > 0) }' || return 1
  return 0
}

# Manda algo a la Papelera sin pisar lo que ya haya allí con el mismo nombre.
mover_a_papelera() {
  local item="$1"
  local papelera="$HOME/.Trash"
  local nombre destino contador

  [ -e "$item" ] || return 0
  mkdir -p "$papelera" 2>/dev/null || return 1

  nombre=${item##*/}
  destino="$papelera/$nombre"
  contador=2

  while [ -e "$destino" ]; do
    destino="$papelera/${nombre} ($contador)"
    contador=$((contador + 1))
  done

  mv "$item" "$destino"
}

DESCARGAS="$HOME/Downloads"
[ -d "$DESCARGAS" ] || fallar 'No encuentro tu carpeta de Descargas.'

command -v ffmpeg >/dev/null 2>&1 || \
  fallar 'Me falta FFmpeg. Instálalo con: brew install ffmpeg'
command -v ffprobe >/dev/null 2>&1 || \
  fallar 'No encuentro ffprobe. Prueba reinstalando FFmpeg con: brew reinstall ffmpeg'
command -v diskutil >/dev/null 2>&1 || \
  fallar 'No encuentro diskutil, que viene con macOS.'
command -v plutil >/dev/null 2>&1 || \
  fallar 'No encuentro plutil, que viene con macOS.'
command -v perl >/dev/null 2>&1 || \
  fallar 'No encuentro Perl, que necesito para ordenar los videos.'

echo '=================================='
echo '   CANVA TV - TU VIDEO EN UN CLIC'
echo '=================================='
echo

# ------------------------------------------------------------
# 1. Buscar tu descarga más reciente
# ------------------------------------------------------------

ORIGEN=''
TIPO_ORIGEN=''
MEJOR_CREACION=-1
MEJOR_MODIFICACION=-1

while IFS= read -r -d '' CANDIDATO; do
  NOMBRE=${CANDIDATO##*/}

  # Quitamos mayúsculas, espacios y símbolos para reconocer todas las variantes:
  #   VIDEOTV (2)       -> videotv2
  #   VIDEO_TV (3).zip  -> videotv3zip
  #   VIDEOTV.zip(2)    -> videotvzip2
  NORMALIZADO=$(printf '%s' "$NOMBRE" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -d '[:space:]_().-')

  ES_VALIDO=0
  TIPO=''

  if [ -d "$CANDIDATO" ]; then
    if [[ "$NORMALIZADO" =~ ^videotv[0-9]*$ ]]; then
      if find "$CANDIDATO" -type f \
        \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \) \
        -print -quit 2>/dev/null | grep -q .; then
        ES_VALIDO=1
        TIPO='carpeta'
      fi
    fi
  elif [ -f "$CANDIDATO" ]; then
    if [[ "$NORMALIZADO" =~ ^videotv[0-9]*zip[0-9]*$ ]]; then
      ES_VALIDO=1
      TIPO='zip'
    fi
  fi

  [ "$ES_VALIDO" -eq 1 ] || continue

  CREACION=$(stat -f '%B' "$CANDIDATO" 2>/dev/null || printf 0)
  MODIFICACION=$(stat -f '%m' "$CANDIDATO" 2>/dev/null || printf 0)
  [ "${CREACION:-0}" -gt 0 ] || CREACION=$MODIFICACION

  if [ "$CREACION" -gt "$MEJOR_CREACION" ] || \
     { [ "$CREACION" -eq "$MEJOR_CREACION" ] && \
       [ "$MODIFICACION" -gt "$MEJOR_MODIFICACION" ]; }; then
    ORIGEN=$CANDIDATO
    TIPO_ORIGEN=$TIPO
    MEJOR_CREACION=$CREACION
    MEJOR_MODIFICACION=$MODIFICACION
  fi
done < <(find "$DESCARGAS" -maxdepth 1 \( -type f -o -type d \) -print0 2>/dev/null)

[ -n "$ORIGEN" ] || fallar \
  'No encontré ninguna descarga VIDEOTV / VIDEO_TV en Descargas. ¿Ya terminó de bajarse?'

echo "Encontré: ${ORIGEN##*/}"
echo "Tipo: $TIPO_ORIGEN"

# ------------------------------------------------------------
# 2. Preparar un espacio de trabajo temporal
# ------------------------------------------------------------

TRABAJO=$(mktemp -d "${TMPDIR:-/tmp/}canva_tv.XXXXXXXX") || \
  fallar 'No pude crear la carpeta temporal.'
trap 'rm -rf "$TRABAJO"' EXIT

mkdir -p "$TRABAJO/extraidos" "$TRABAJO/clips"

if [ "$TIPO_ORIGEN" = 'zip' ]; then
  command -v ditto >/dev/null 2>&1 || \
    fallar 'No encuentro ditto (viene con macOS) para abrir el ZIP.'

  unzip -tq "$ORIGEN" >/dev/null 2>&1 || \
    fallar 'El ZIP parece incompleto o dañado. Espera a que termine de descargarse y vuelve a intentarlo.'

  echo 'Abriendo el ZIP...'
  ditto -x -k "$ORIGEN" "$TRABAJO/extraidos" || \
    fallar 'No pude descomprimir el ZIP.'
  FUENTE="$TRABAJO/extraidos"
else
  FUENTE="$ORIGEN"
fi

# ------------------------------------------------------------
# 3. Poner los clips en orden y prepararlos (imagen + sonido)
# ------------------------------------------------------------

LISTA="$TRABAJO/lista_ffmpeg.txt"
: > "$LISTA"
CONTADOR=0

while IFS= read -r -d '' VIDEO; do
  case "$VIDEO" in
    */__MACOSX/*|*/._*) continue ;;
  esac

  CONTADOR=$((CONTADOR + 1))
  CLIP=$(printf '%s/clips/clip_%05d.mp4' "$TRABAJO" "$CONTADOR")

  printf '\n[%d] %s\n' "$CONTADOR" "${VIDEO##*/}"

  # ¿Este clip trae sonido?
  TIENE_AUDIO=0
  if ffprobe -v error -select_streams a:0 \
      -show_entries stream=index -of csv=p=0 "$VIDEO" 2>/dev/null | grep -q .; then
    TIENE_AUDIO=1
  fi

  if [ "$TIENE_AUDIO" -eq 1 ]; then
    # Nos quedamos con la música/audio original que puso Canva.
    ffmpeg -hide_banner -loglevel error -nostdin -y \
      -i "$VIDEO" \
      -map 0:v:0 -map 0:a:0 \
      -vf 'fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p' \
      -af 'aresample=48000:async=1:first_pts=0' \
      -c:v libx264 -preset fast -crf 20 -r 30 -pix_fmt yuv420p \
      -c:a aac -b:a 192k -ar 48000 -ac 2 \
      "$CLIP" || fallar "No pude procesar este clip: ${VIDEO##*/}"
  else
    # Si algún clip llega mudo, le ponemos silencio para que la unión
    # no se rompa y todo siga sincronizado.
    echo '    Este clip no trae audio, le pongo un poco de silencio.'
    ffmpeg -hide_banner -loglevel error -nostdin -y \
      -i "$VIDEO" \
      -f lavfi -i 'anullsrc=channel_layout=stereo:sample_rate=48000' \
      -map 0:v:0 -map 1:a:0 \
      -vf 'fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p' \
      -c:v libx264 -preset fast -crf 20 -r 30 -pix_fmt yuv420p \
      -c:a aac -b:a 192k -ar 48000 -ac 2 \
      -shortest \
      "$CLIP" || fallar "No pude procesar este clip: ${VIDEO##*/}"
  fi

  printf "file '%s'\n" "$CLIP" >> "$LISTA"

done < <(
  find "$FUENTE" -type f \
    \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \) \
    -print0 |
  perl -0ne '
    chomp;
    push @archivos, $_;
    END {
      sub clave {
        my $ruta = shift;
        my ($nombre) = $ruta =~ m{([^/]+)$};
        $nombre = lc($nombre // $ruta);
        $nombre =~ s/(\d+)/sprintf("%020d", $1)/ge;
        return "$nombre\0" . lc($ruta);
      }
      print join "\0", sort { clave($a) cmp clave($b) } @archivos;
      print "\0" if @archivos;
    }
  '
)

[ "$CONTADOR" -gt 0 ] || \
  fallar 'No encontré videos MP4, MOV o M4V dentro de la descarga.'

# ------------------------------------------------------------
# 4. Juntar todo en un solo video
# ------------------------------------------------------------

echo
echo "Uniendo $CONTADOR videos, con su audio original..."

ARCHIVO_FINAL="VIDEOTV.mp4"
FINAL_TEMPORAL="$TRABAJO/$ARCHIVO_FINAL"

ffmpeg -hide_banner -loglevel error -nostdin -y \
  -f concat -safe 0 -i "$LISTA" \
  -c copy -movflags +faststart \
  "$FINAL_TEMPORAL" || \
  fallar 'No pude unir los videos.'

echo
echo '[Revisión] Comprobando imagen, sonido y duración...'
verificar_video "$FINAL_TEMPORAL" || \
  fallar 'El video se creó, pero no pasó la revisión de calidad. Mejor no lo guardo.'
echo '✓ El video final está perfecto.'

# ------------------------------------------------------------
# 5. Ver si hay una USB lista para recibirlo
# ------------------------------------------------------------

USB_CANDIDATAS=0
USB_DESTINO=''
FINAL_KB=$(du -k "$FINAL_TEMPORAL" | awk '{print $1}')

for VOLUMEN in /Volumes/*; do
  [ -d "$VOLUMEN" ] || continue

  INFO=$(diskutil info -plist "$VOLUMEN" 2>/dev/null) || continue

  BUS=$(printf '%s' "$INFO" | \
    plutil -extract BusProtocol raw -o - - 2>/dev/null || true)
  [ "$BUS" = 'USB' ] || continue

  INTERNO=$(printf '%s' "$INFO" | \
    plutil -extract Internal raw -o - - 2>/dev/null || true)
  [ "$INTERNO" != 'true' ] || continue

  SOLO_LECTURA=$(printf '%s' "$INFO" | \
    plutil -extract ReadOnlyVolume raw -o - - 2>/dev/null || true)
  [ "$SOLO_LECTURA" != 'true' ] || continue

  [ -w "$VOLUMEN" ] || continue

  # Que tenga espacio de sobra (el video + 100 MB de margen).
  LIBRE_KB=$(df -Pk "$VOLUMEN" | awk 'NR==2 {print $4}')
  [ "${LIBRE_KB:-0}" -gt $((FINAL_KB + 102400)) ] || continue

  USB_CANDIDATAS=$((USB_CANDIDATAS + 1))
  USB_DESTINO=$VOLUMEN
done

if [ "$USB_CANDIDATAS" -eq 1 ]; then
  DESTINO=$USB_DESTINO
  echo
  echo "Encontré tu USB: ${DESTINO##*/}"
elif [ "$USB_CANDIDATAS" -eq 0 ]; then
  DESTINO=$DESCARGAS
  echo
  echo 'No veo ninguna USB que sirva, así que lo dejo en Descargas.'
else
  DESTINO=$DESCARGAS
  echo
  echo 'Hay varias USB conectadas. Para no equivocarme, lo dejo en Descargas.'
fi

# ------------------------------------------------------------
# 6. Guardar con cuidado y comprobar la copia
# ------------------------------------------------------------

GUARDAR_EN() {
  local carpeta="$1"
  local salida="$carpeta/$ARCHIVO_FINAL"
  local parcial="$salida.parcial"

  rm -f "$parcial" 2>/dev/null || true

  cp "$FINAL_TEMPORAL" "$parcial" || {
    rm -f "$parcial" 2>/dev/null || true
    return 1
  }

  sync

  verificar_video "$parcial" || {
    rm -f "$parcial" 2>/dev/null || true
    return 1
  }

  mv -f "$parcial" "$salida" || {
    rm -f "$parcial" 2>/dev/null || true
    return 1
  }

  sync
  verificar_video "$salida" || return 1

  printf '%s\n' "$salida"
  return 0
}

echo
echo '[Guardado] Copiando VIDEOTV.mp4...'

GUARDADO_EN_USB=0

if SALIDA=$(GUARDAR_EN "$DESTINO"); then
  if [ "$USB_CANDIDATAS" -eq 1 ] && [ "$DESTINO" = "$USB_DESTINO" ]; then
    GUARDADO_EN_USB=1
  fi
else
  if [ "$DESTINO" = "$DESCARGAS" ]; then
    fallar 'No pude guardar el video en Descargas.'
  fi

  echo 'La copia en la USB no salió bien.'
  echo 'No te preocupes, guardo una copia segura en Descargas...'
  SALIDA=$(GUARDAR_EN "$DESCARGAS") || \
    fallar 'Tampoco pude guardarlo en Descargas.'
  GUARDADO_EN_USB=0
fi

echo '✓ Copia guardada y comprobada.'

# ------------------------------------------------------------
# 7. Ordenar un poco: las descargas de Canva a la Papelera
# ------------------------------------------------------------
#
# Esto SOLO pasa cuando ya sabemos que VIDEOTV.mp4 quedó bien.
# Las carpetas y ZIP VIDEOTV / VIDEO_TV van a la Papelera (no se borran
# del todo) y VIDEOTV.mp4 nunca se toca.

echo
echo '[Limpieza] Mandando las descargas viejas de VIDEOTV a la Papelera...'

MOVIDOS=0
FALLOS_LIMPIEZA=0

while IFS= read -r -d '' ITEM; do
  NOMBRE=${ITEM##*/}

  # El video final es sagrado.
  [ "$NOMBRE" = "VIDEOTV.mp4" ] && continue

  NORMALIZADO=$(printf '%s' "$NOMBRE" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -d '[:space:]_().-')

  ES_DESCARGA_CANVA=0

  if [ -d "$ITEM" ] && [[ "$NORMALIZADO" =~ ^videotv[0-9]*$ ]]; then
    ES_DESCARGA_CANVA=1
  elif [ -f "$ITEM" ] && [[ "$NORMALIZADO" =~ ^videotv[0-9]*zip[0-9]*$ ]]; then
    ES_DESCARGA_CANVA=1
  fi

  [ "$ES_DESCARGA_CANVA" -eq 1 ] || continue

  if mover_a_papelera "$ITEM"; then
    MOVIDOS=$((MOVIDOS + 1))
  else
    FALLOS_LIMPIEZA=$((FALLOS_LIMPIEZA + 1))
  fi
done < <(find "$DESCARGAS" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print0 2>/dev/null)

if [ "$MOVIDOS" -gt 0 ]; then
  echo "✓ $MOVIDOS descarga(s) en la Papelera."
else
  echo 'No había descargas viejas que limpiar.'
fi

if [ "$FALLOS_LIMPIEZA" -gt 0 ]; then
  echo "Ojo: $FALLOS_LIMPIEZA elemento(s) no se pudieron mover a la Papelera."
fi

# ------------------------------------------------------------
# 8. Expulsar la USB (si la usamos)
# ------------------------------------------------------------

USB_EXPULSADA=0
USB_NOMBRE=''

if [ "$GUARDADO_EN_USB" -eq 1 ]; then
  USB_NOMBRE=${USB_DESTINO##*/}
  echo
  echo "[USB] Sincronizando y expulsando $USB_NOMBRE..."
  sync
  sleep 1

  if diskutil eject "$USB_DESTINO" >/dev/null 2>&1; then
    USB_EXPULSADA=1
    echo '✓ USB expulsada. Ya puedes sacarla.'
  else
    echo 'Ojo: el video quedó guardado, pero macOS no pudo expulsar la USB.'
    echo 'Expúlsala desde Finder antes de sacarla.'
  fi
fi

# ------------------------------------------------------------
# 9. El resumen final
# ------------------------------------------------------------

echo
echo '=================================='
echo '             ¡LISTO!'
echo '=================================='
printf '%s videos unidos.\n' "$CONTADOR"
echo 'Con su audio original.'
echo 'Video final revisado.'

if [ "$GUARDADO_EN_USB" -eq 1 ]; then
  echo "Guardado en la USB: $USB_NOMBRE/VIDEOTV.mp4"
  if [ "$USB_EXPULSADA" -eq 1 ]; then
    MENSAJE_FINAL="¡Listo! VIDEOTV.mp4 quedó guardado y comprobado en la USB \"$USB_NOMBRE\". Ya la expulsé, puedes sacarla tranquilo."
  else
    MENSAJE_FINAL="¡Listo! VIDEOTV.mp4 quedó guardado y comprobado en la USB \"$USB_NOMBRE\", pero no pude expulsarla sola. Expúlsala desde Finder antes de sacarla."
  fi
else
  printf 'Guardado en: %s\n' "$SALIDA"
  MENSAJE_FINAL="¡Listo! VIDEOTV.mp4 quedó guardado y comprobado en Descargas."
  open -R "$SALIDA" 2>/dev/null || true
fi

if [ "$MOVIDOS" -gt 0 ]; then
  MENSAJE_FINAL="$MENSAJE_FINAL Además, mandé $MOVIDOS descarga(s) VIDEOTV a la Papelera."
fi

avisar "$MENSAJE_FINAL"

read -r -p 'Pulsa Enter para cerrar... ' _ || true

if [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ]; then
  (sleep 0.2; osascript -e 'tell application "Terminal" to close front window' >/dev/null 2>&1) &
fi

exit 0