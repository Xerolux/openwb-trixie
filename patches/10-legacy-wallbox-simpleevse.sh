#!/bin/bash
# ============================================================================
# Patch: Legacy Wallbox - SimpleEVSE WiFi evcc-geprüft
# ============================================================================
# Id: legacy-wallbox-simpleevse
# Name: SimpleEVSE WiFi Legacy evcc-geprüft
# Desc: SimpleEVSE WiFi per HTTP-API (/getParameters, /setCurrent, /setStatus),
#       Phasenerkennung best-effort, kompatibel mit openWB 1.9 Pfaden.
# File: packages/modules/chargepoints/legacy_simpleevse_evcc/
# ============================================================================

PATCH_ID="legacy-wallbox-simpleevse"
PATCH_NAME="SimpleEVSE WiFi Legacy evcc-geprüft"
PATCH_DESC="SimpleEVSE WiFi HTTP-API, setStatus/setCurrent, best-effort Phasen"
PATCH_MODULE="legacy_simpleevse_evcc"
PATCH_MARKER="# openwb-trixie-patch: legacy-wallbox-simpleevse"

_repo_base() {
    local base
    base="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
    if [ -n "$base" ] && [ -d "$base/openwb_legacy_wallboxes_evcc_optimized" ]; then
        echo "$base"
        return 0
    fi
    if [ -n "${PATCHES_SRC_DIR:-}" ] && [ -d "${PATCHES_SRC_DIR}/openwb_legacy_wallboxes_evcc_optimized" ]; then
        echo "$PATCHES_SRC_DIR"
        return 0
    fi
    if [ -n "${REPO_DIR:-}" ] && [ -d "${REPO_DIR}/openwb_legacy_wallboxes_evcc_optimized" ]; then
        echo "$REPO_DIR"
        return 0
    fi
    if [ -d "/home/openwb/openwb-trixie/openwb_legacy_wallboxes_evcc_optimized" ]; then
        echo "/home/openwb/openwb-trixie"
        return 0
    fi
    echo ""
    return 1
}

patch_meta() {
    echo "id:   $PATCH_ID"
    echo "name: $PATCH_NAME"
    echo "desc: $PATCH_DESC"
    echo "module: $PATCH_MODULE"
}

patch_check() {
    local target="${OPENWB_DIR:-/var/www/html/openWB}/packages/modules/chargepoints/$PATCH_MODULE/chargepoint_module.py"
    [ -f "$target" ] && grep -q "$PATCH_MARKER" "$target" 2>/dev/null
}

patch_apply() {
    local owb="${OPENWB_DIR:-/var/www/html/openWB}"
    local target_dir="$owb/packages/modules/chargepoints/$PATCH_MODULE"
    local repo
    repo=$(_repo_base)
    if [ -z "$repo" ]; then
        echo "  FEHLER: Repository nicht gefunden (Quell-Dateien fuer $PATCH_MODULE)"
        return 1
    fi
    local src_dir="$repo/openwb_legacy_wallboxes_evcc_optimized/packages/modules/chargepoints/$PATCH_MODULE"
    if [ ! -d "$src_dir" ]; then
        echo "  FEHLER: Quell-Verzeichnis nicht gefunden: $src_dir"
        return 1
    fi

    sudo mkdir -p "$target_dir"

    for f in "$src_dir"/*.py; do
        [ -f "$f" ] || continue
        sudo cp "$f" "$target_dir/$(basename "$f")"
    done

    local module_file="$target_dir/chargepoint_module.py"
    if [ -f "$module_file" ] && ! grep -q "$PATCH_MARKER" "$module_file"; then
        echo "$PATCH_MARKER" | sudo tee -a "$module_file" > /dev/null
    fi

    if patch_check; then
        echo "  OK: $PATCH_NAME installiert ($target_dir)"
        return 0
    else
        echo "  FEHLER: Installation konnte nicht verifiziert werden"
        return 1
    fi
}

patch_revert() {
    local target_dir="${OPENWB_DIR:-/var/www/html/openWB}/packages/modules/chargepoints/$PATCH_MODULE"
    if [ -d "$target_dir" ]; then
        sudo rm -rf "$target_dir"
        echo "  Revert OK: $PATCH_NAME entfernt ($target_dir)"
    else
        echo "  Revert OK: $PATCH_NAME war nicht installiert"
    fi
    return 0
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    true
else
    patch_meta
fi
