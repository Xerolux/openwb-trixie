#!/bin/bash
# ============================================================================
# Patch: Kein Reboot nach Update
# ============================================================================
# Id: no-reboot-on-update
# Name: Kein Reboot nach Update
# Desc: Ersetzt 'sudo reboot now' in update_self.sh durch Service-Neustart.
#       Spart Wartezeit, besonders bei Multi-Wallbox-Setups.
# File: runs/update_self.sh
# ============================================================================

PATCH_ID="no-reboot-on-update"
PATCH_NAME="Kein Reboot nach Update"
PATCH_DESC="Ersetzt reboot durch Service-Neustart (schneller, kein Warten)"
PATCH_FILE="runs/update_self.sh"

MARKER_ORIGINAL='sudo reboot now &'
MARKER_PATCHED='# openwb-trixie-patch: no-reboot-on-update (was: sudo reboot now &)'

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
        echo "  WARNUNG: Original-Code nicht gefunden"
        echo "  Suche nach: $MARKER_ORIGINAL"
        return 1
    fi

    sudo cp "$target" "${target}.pre-${PATCH_ID}.$(date +%Y%m%d%H%M%S)"

    sudo sed -i "s|${MARKER_ORIGINAL}|${MARKER_PATCHED}\n\tsudo systemctl restart openwb2\n\tsudo systemctl restart openwb-simpleAPI|g" "$target"

    if patch_check; then
        echo "  OK: $PATCH_NAME angewendet (reboot → service restart)"
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

    if ! patch_check; then
        echo "  Patch nicht aktiv: $PATCH_NAME"
        return 0
    fi

    sudo sed -i "/${MARKER_PATCHED}/d" "$target"
    sudo sed -i "/sudo systemctl restart openwb2/d" "$target"
    sudo sed -i "/sudo systemctl restart openwb-simpleAPI/d" "$target"
    echo -e "\tsudo reboot now &" | sudo tee -a "$target" > /dev/null

    if ! patch_check; then
        echo "  Revert OK: $PATCH_NAME"
        return 0
    else
        echo "  FEHLER beim Revert"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    true
else
    patch_meta
fi
