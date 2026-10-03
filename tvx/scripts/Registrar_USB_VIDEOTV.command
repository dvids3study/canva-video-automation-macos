#!/bin/bash
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"
BASE="$HOME/Library/Application Support/VIDEOTV"; ALLOW="$BASE/usb_allowlist.txt"; mkdir -p "$BASE"; touch "$ALLOW"
COUNT=0; FOUND_UUID=""; FOUND_NAME=""
for V in /Volumes/*; do [ -d "$V" ] || continue; INFO=$(diskutil info -plist "$V" 2>/dev/null) || continue; BUS=$(printf '%s' "$INFO" | plutil -extract BusProtocol raw -o - - 2>/dev/null || true); INTERNAL=$(printf '%s' "$INFO" | plutil -extract Internal raw -o - - 2>/dev/null || true); READONLY=$(printf '%s' "$INFO" | plutil -extract ReadOnlyVolume raw -o - - 2>/dev/null || true); UUID=$(printf '%s' "$INFO" | plutil -extract VolumeUUID raw -o - - 2>/dev/null || true); [ "$BUS" = USB ] || continue; [ "$INTERNAL" != true ] || continue; [ "$READONLY" != true ] || continue; [ -w "$V" ] || continue; [ -n "$UUID" ] || continue; COUNT=$((COUNT+1)); FOUND_UUID="$UUID"; FOUND_NAME=${V##*/}; done
if [ "$COUNT" -eq 0 ]; then osascript -e 'display alert "VIDEOTV" message "No encontré una memoria USB externa y escribible."' >/dev/null; exit 1; fi
if [ "$COUNT" -gt 1 ]; then osascript -e 'display alert "VIDEOTV" message "Hay más de una USB conectada. Deja conectada únicamente la memoria que quieras registrar."' >/dev/null; exit 1; fi
if ! grep -Fxq "$FOUND_UUID" "$ALLOW"; then printf '%s\n' "$FOUND_UUID" >> "$ALLOW"; fi
osascript -e 'on run argv' -e 'display alert "USB registrada" message ("VIDEOTV reconocerá automáticamente la memoria: " & item 1 of argv)' -e 'end run' "$FOUND_NAME" >/dev/null
echo "USB registrada: $FOUND_NAME ($FOUND_UUID)"
