#!/bin/bash
# Integracion TVX/Apple Mail. Nunca reintenta un envio automaticamente.
set -uo pipefail
BASE="$HOME/Library/Application Support/VIDEOTV"
STATUS="$BASE/status.tsv"
SCRIPT="$BASE/VIDEOTV_Mail.applescript"
MODE_FILE="$BASE/mail_mode.txt"
LOG="$BASE/mail.log"
MP4="${1:-}"
mkdir -p "$BASE"
exec >>"$LOG" 2>&1

clean_field() { printf '%s' "$1" | tr '\t\r\n' '   '; }
status_write() {
    local tmp="$STATUS.tmp.$$"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(clean_field "$1")" "$(clean_field "$2")" "$(clean_field "${3:-}")" \
      "${4:-98}" "${5:-0}" "$(clean_field "${6:-}")" > "$tmp"
    mv -f "$tmp" "$STATUS"
}

run_with_timeout() {
    local limit="$1"; shift
    local pid waited=0 rc
    "$@" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$limit" ]; then
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 2
        waited=$((waited + 2))
    done
    wait "$pid"
    rc=$?
    return "$rc"
}

last_line() {
    printf '%s\n' "$1" | tail -n 1 | tr -d '\r'
}

if [ ! -s "$MP4" ] || [ ! -f "$SCRIPT" ]; then
    echo "Video o AppleScript no disponible" >&2
    exit 12
fi

MODE="off"
[ -f "$MODE_FILE" ] && MODE="$(tr -d '[:space:]' < "$MODE_FILE")"
[ "${TVX_MAIL_FORCE_PREVIEW:-0}" = "1" ] && MODE="preview"
case "$MODE" in
    preview|send|off) ;;
    *) echo "Modo no permitido: $MODE" >&2; exit 12 ;;
esac
if [ "$MODE" = "off" ]; then
    echo "Mail desactivado (off). No se prepara nada."
    exit 13
fi

# Mail Drop admite hasta 5 GB por adjunto con iCloud. El limite se puede bajar
# en mail_max_mb.txt si usas otro proveedor (Gmail, por ejemplo, admite ~25 MB).
MAX_FILE="$BASE/mail_max_mb.txt"
MAX_MB=5000
if [ -f "$MAX_FILE" ]; then
    MAX_MB=$(tr -dc '0-9' < "$MAX_FILE")
fi
case "$MAX_MB" in
    ''|*[!0-9]*) MAX_MB=5000 ;;
esac
[ "$MAX_MB" -ge 1 ] || MAX_MB=5000

SIZE_BYTES=$(wc -c < "$MP4" | tr -d ' ')
MAX_BYTES=$(( MAX_MB * 1000000 ))
SIZE_MB=$(( (SIZE_BYTES + 500000) / 1000000 ))
if [ "$SIZE_BYTES" -gt "$MAX_BYTES" ]; then
    echo "SKIP | archivo de ${SIZE_MB} MB; limite ${MAX_MB} MB"
    status_write success "Video guardado" "Demasiado grande para Mail (${SIZE_MB} MB; límite ${MAX_MB} MB) · No se envió" 100 0 "$MP4"
    exit 14
fi

REFERENCE="$(uuidgen 2>/dev/null || date +%s-$$)"
# Guardar referencia incluso si no se llega a confirmar el envio.
printf '%s\t%s\t%s\t%s\n' "$REFERENCE" "$(date -u +%FT%TZ)" "$MODE" "$MP4" \
    >> "$BASE/mail_attempts.tsv"

status_write sending "Preparando Apple Mail" "VIDEOTV.mp4 · cuenta configurada" 98 0 ""
echo "$(date) | $REFERENCE | mode=$MODE | file=$MP4"

# Preparar un borrador con un video grande puede tardar. Damos 15 minutos
# al borrador y 30 minutos al envio real.
CREATE_TIMEOUT=900
[ "$MODE" = "send" ] && CREATE_TIMEOUT=1800
result=$(run_with_timeout "$CREATE_TIMEOUT" /usr/bin/osascript "$SCRIPT" create "$MP4" "$REFERENCE" "$MODE" 2>&1)
rc=$?
echo "create rc=$rc: $result"
if [ "$rc" -eq 124 ]; then
    echo "TIMEOUT | $REFERENCE | Apple Mail no respondio a tiempo"
    exit 12
fi
if [ "$rc" -ne 0 ]; then
    echo "ERROR | $REFERENCE | $result"
    exit 12
fi

result_last=$(last_line "$result")

if [ "$MODE" = "preview" ]; then
    [ "$result_last" = "PREVIEW" ] || exit 12
    status_write preview "Borrador de Mail listo" "Revísalo y envíalo tú" 100 0 "$MP4"
    echo "PREVIEW | $REFERENCE | revisar borrador (no enviado)"
    exit 10
fi

[ "$result_last" = "SUBMITTED" ] || exit 12

# Mail ya acepto el mensaje: el envio real (y Mail Drop) queda a cargo de Mail.
# No bloqueamos el popup esperando una copia en "Enviados": en cuentas iCloud
# esa copia puede no aparecer nunca aunque el correo si se haya enviado.
status_write success "VIDEOTV listo" "Correo entregado a Mail · MP4 en Descargas" 100 0 "$MP4"
echo "SUBMITTED | $REFERENCE | Mail se encarga del envio"
exit 0
