#!/bin/bash
# ============================================================================
# Patch: Force Secondary Chargepoint Update
# ============================================================================
# Id: force-secondary-update
# Name: Sekundaere Wallboxen immer updaten
# Desc: Entfernt die Branch-Pruefung beim Update sekundaerer Wallboxen.
#       Normalerweise werden sekundaere Wallboxen nur geupdatet, wenn sie auf
#       dem "Release"-Branch sind. Dieser Patch entfernt diese Einschraenkung.
# File: packages/helpermodules/command.py
# ============================================================================
#
# Alle Patches muessen folgende Funktionen bereitstellen:
#   patch_meta()    -> gibt Metadaten aus (id, name, desc, file)
#   patch_check()   -> Exit 0 = bereits gepatcht, Exit 1 = nicht gepatcht
#   patch_apply()   -> wendet den Patch an
#   patch_revert()  -> macht den Patch rueckgaengig
#
# Umgebungsvariablen (vom Aufrufer gesetzt):
#   OPENWB_DIR      -> /var/www/html/openWB
#   VENV_DIR        -> /opt/openwb-venv  (oder leer wenn kein venv)
# ============================================================================

PATCH_ID="force-secondary-update"
PATCH_NAME="Sekundaere Wallboxen immer updaten"
PATCH_DESC="Entfernt Branch-Pruefung beim Update sekundaer Wallboxen (immer updaten, egal welcher Branch)"
PATCH_FILE="packages/helpermodules/command.py"

# Marker der im Code gesucht/ersetzt wird
MARKER_ORIGINAL='cp.chargepoint.data.get.current_branch == "Release"'
MARKER_PATCHED='# openwb-trixie-patch: force-secondary-update (was: current_branch == "Release")'

patch_meta() {
    echo "id:   $PATCH_ID"
    echo "name: $PATCH_NAME"
    echo "desc: $PATCH_DESC"
    echo "file: $PATCH_FILE"
}

patch_check() {
    local target="${OPENWB_DIR:-/var/www/html/openWB}/$PATCH_FILE"
    if [ ! -f "$target" ]; then
        return 1
    fi
    grep -q "$MARKER_PATCHED" "$target" 2>/dev/null
}

patch_apply() {
    local target="${OPENWB_DIR:-/var/www/html/openWB}/$PATCH_FILE"
    if [ ! -f "$target" ]; then
        echo "  FEHLER: $target nicht gefunden"
        return 1
    fi

    if patch_check; then
        echo "  Bereits gepatcht: $PATCH_NAME"
        return 0
    fi

    if ! grep -q "$MARKER_ORIGINAL" "$target" 2>/dev/null; then
        echo "  WARNUNG: Original-Code nicht gefunden (vielleicht andere Version?)"
        echo "  Suche nach: $MARKER_ORIGINAL"
        return 1
    fi

    sudo cp "$target" "${target}.pre-${PATCH_ID}.$(date +%Y%m%d%H%M%S)"
    sudo sed -i "s|${MARKER_ORIGINAL}|${MARKER_PATCHED}|g" "$target"

    if patch_check; then
        echo "  OK: $PATCH_NAME angewendet"
        return 0
    else
        echo "  FEHLER: Patch konnte nicht verifiziert werden"
        return 1
    fi
}

patch_revert() {
    local target="${OPENWB_DIR:-/var/www/html/openWB}/$PATCH_FILE"
    if [ ! -f "$target" ]; then
        return 0
    fi

    sudo sed -i "s|${MARKER_PATCHED}|${MARKER_ORIGINAL}|g" "$target"

    if ! patch_check; then
        echo "  Revert OK: $PATCH_NAME"
        return 0
    else
        echo "  FEHLER beim Revert"
        return 1
    fi
}

# Wenn direkt aufgerufen: Meta ausgeben
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    true
else
    patch_meta
fi
