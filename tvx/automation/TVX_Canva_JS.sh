#!/bin/bash
# TVX - inicia la descarga de Canva web en Safari usando JavaScript.
# Requiere: Safari > Ajustes > Desarrollador > Permitir JavaScript desde Apple Events.
# Devuelve: CLICKED, MANUAL, NO_JS_OR_TAB
set -u

BASE="$HOME/Library/Application Support/VIDEOTV"
URL_FILE="$BASE/canva_url.txt"
DEFAULT_URL="https://www.canva.com/"
URL="$(head -n 1 "$URL_FILE" 2>/dev/null || true)"
[ -n "$URL" ] || URL="$DEFAULT_URL"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$BASE/canva_js.log"
}

run_js() {
    local js="$1" b64 out
    b64=$(printf '%s' "$js" | base64 | tr -d '\n')
    out=$(osascript <<APPLESCRIPT 2>&1
tell application "Safari"
    set targetWindow to missing value
    repeat with w in windows
        repeat with t in tabs of w
            try
                if (URL of t as text) contains "canva.com/design/" then
                    set current tab of w to t
                    set targetWindow to w
                    exit repeat
                end if
            end try
        end repeat
        if targetWindow is not missing value then exit repeat
    end repeat
    if targetWindow is missing value then return "NO_CANVA_TAB"
    return do JavaScript "eval(atob('$b64'))" in current tab of targetWindow
end tell
APPLESCRIPT
)
    printf '%s' "$out"
}

ensure_tab() {
    local out
    out=$(run_js 'document.title')
    if [ "$out" = "NO_CANVA_TAB" ]; then
        log "No hay pestaña de Canva; abriendo $URL"
        open -a Safari "$URL" >/dev/null 2>&1 || true
        sleep 10
        out=$(run_js 'document.title')
    fi
    case "$out" in
        NO_CANVA_TAB|execution\ error*|"") return 1 ;;
    esac
    log "Pestaña Canva: $out"
    return 0
}

wait_for() {
    local js="$1" not="$2" tries="${3:-12}" out="" i
    for i in $(seq 1 "$tries"); do
        out=$(run_js "$js")
        if [ "$out" != "$not" ]; then
            printf '%s' "$out"
            return 0
        fi
        sleep 1
    done
    printf '%s' "$out"
    return 1
}

JS_DOWNLOADING='(() => ((document.body.innerText || "").includes("Descargando")) ? "YES" : "NO")()'

JS_SHARE='(() => {
  if ((document.body.innerText || "").includes("Compartir el diseño")) return "ALREADY_SHARE";
  const seen = new Set();
  function all(root, out) {
    if (!root || seen.has(root)) return out;
    seen.add(root);
    let els;
    try { els = root.querySelectorAll("*"); } catch (e) { return out; }
    for (const el of els) { out.push(el); if (el.shadowRoot) all(el.shadowRoot, out); }
    return out;
  }
  const b = all(document, []).find(el => {
    if (el.tagName !== "BUTTON") return false;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return false;
    const t = (el.innerText || "").trim();
    const a = (el.getAttribute("aria-label") || "").trim();
    return t === "Compartir" || a === "Compartir" || t === "Share" || a === "Share";
  });
  if (!b) return "NO_SHARE";
  b.click();
  return "SHARE_CLICKED";
})()'

JS_DESCARGAR='(() => {
  const seen = new Set();
  function all(root, out) {
    if (!root || seen.has(root)) return out;
    seen.add(root);
    let els;
    try { els = root.querySelectorAll("*"); } catch (e) { return out; }
    for (const el of els) { out.push(el); if (el.shadowRoot) all(el.shadowRoot, out); }
    return out;
  }
  const b = all(document, []).find(el => {
    if (el.tagName !== "BUTTON") return false;
    const r = el.getBoundingClientRect();
    if (r.width <= 0) return false;
    const t = (el.innerText || "").trim();
    const a = (el.getAttribute("aria-label") || "").trim();
    return (t === "Descargar" || a === "Descargar");
  });
  if (!b) return "NO_DESCARGAR";
  b.click();
  return "DESCARGAR_CLICKED";
})()'

JS_MP4_CHECK='(() => {
  const b = document.querySelector("button[role=\"combobox\"][aria-label=\"Tipo de archivo\"]");
  if (!b) return "NO_COMBO";
  if ((b.innerText || "").includes("Video MP4")) return "ALREADY_MP4";
  b.click();
  return "COMBO_OPENED";
})()'

JS_MP4_OPTION='(() => {
  const seen = new Set();
  function all(root, out) {
    if (!root || seen.has(root)) return out;
    seen.add(root);
    let els;
    try { els = root.querySelectorAll("*"); } catch (e) { return out; }
    for (const el of els) { out.push(el); if (el.shadowRoot) all(el.shadowRoot, out); }
    return out;
  }
  const b = all(document, []).find(el => el.tagName === "BUTTON" && el.getAttribute("role") === "option" && (el.innerText || "").includes("Video MP4"));
  if (!b) return "NO_MP4_OPTION";
  b.click();
  return "MP4_SELECTED";
})()'

JS_TODO='(() => {
  const b = [...document.querySelectorAll("button[role=\"radio\"]")].find(el => (el.innerText || "").trim() === "Todo");
  if (!b) return "NO_TODO";
  if (b.getAttribute("aria-checked") === "true") return "TODO_ALREADY";
  b.click();
  return "TODO_SELECTED";
})()'

JS_FINAL='(() => {
  const btns = [...document.querySelectorAll("button")].filter(el => {
    const t = (el.innerText || "").trim();
    const r = el.getBoundingClientRect();
    return t === "Descargar" && r.width > 200 && r.height >= 30;
  });
  if (!btns.length) return "NO_FINAL_DESCARGAR";
  btns[0].click();
  return "FINAL_DESCARGAR_CLICKED";
})()'

JS_STATUS='(() => {
  const t = (document.body.innerText || "").replace(/\s+/g, " ");
  if (t.includes("Descargando") || t.includes("Video MP4 -")) return "DOWNLOAD_STARTED";
  return "NO_STATUS";
})()'

main() {
    mkdir -p "$BASE"
    if ! ensure_tab; then
        echo "NO_JS_OR_TAB"
        return 0
    fi

    local out
    out=$(run_js "$JS_DOWNLOADING")
    if [ "$out" = "YES" ]; then
        log "Ya hay una exportación en curso; TVX espera el archivo."
        echo "CLICKED"
        return 0
    fi

    out=$(run_js "$JS_SHARE")
    log "Compartir: $out"
    case "$out" in
        NO_SHARE) echo "MANUAL"; return 0 ;;
    esac
    if [ "$out" = "SHARE_CLICKED" ]; then sleep 2; fi

    out=$(wait_for "$JS_DESCARGAR" "NO_DESCARGAR" 12)
    log "Descargar (Compartir): $out"
    if [ "$out" = "NO_DESCARGAR" ]; then
        # Si el diálogo de descarga ya estaba abierto, seguimos.
        out=$(run_js 'document.querySelector("button[role=\"combobox\"][aria-label=\"Tipo de archivo\"]") ? "DIALOG_OPEN" : "NO_DIALOG"')
        log "Diálogo: $out"
        [ "$out" = "DIALOG_OPEN" ] || { echo "MANUAL"; return 0; }
    fi
    sleep 2

    out=$(wait_for "$JS_MP4_CHECK" "NO_COMBO" 12)
    log "MP4 check: $out"
    if [ "$out" = "COMBO_OPENED" ]; then
        sleep 1
        out=$(run_js "$JS_MP4_OPTION")
        log "MP4 option: $out"
        [ "$out" = "MP4_SELECTED" ] || { echo "MANUAL"; return 0; }
        sleep 1
    elif [ "$out" != "ALREADY_MP4" ]; then
        echo "MANUAL"; return 0
    fi

    out=$(wait_for "$JS_TODO" "NO_TODO" 8)
    log "Todo: $out"
    case "$out" in
        NO_TODO) echo "MANUAL"; return 0 ;;
    esac
    sleep 1

    out=$(wait_for "$JS_FINAL" "NO_FINAL_DESCARGAR" 8)
    log "Descargar final: $out"
    if [ "$out" != "FINAL_DESCARGAR_CLICKED" ]; then
        echo "MANUAL"
        return 0
    fi

    sleep 2
    out=$(run_js "$JS_STATUS")
    log "Estado: $out"
    echo "CLICKED"
    return 0
}

main
