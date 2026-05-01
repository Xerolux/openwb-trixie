#!/bin/bash
# ============================================================================
# Patch: Raspberry Pi Beta-Repositories aktivieren
# ============================================================================
# Id: rpi-beta-repos
# Name: Pi Beta-/Test-Repositories aktivieren
# Desc: Aktiviert Raspberry Pi Beta- und Test-Repositorys fuer Zugriff
#       auf aktuellere Pakete (Kernel, Firmware, rpi-swap etc.).
#       Nur fuer Raspberry Pi mit Raspberry Pi OS / Debian.
# File: /etc/apt/sources.list.d/raspi-beta.list
# Arch: rpi
# ============================================================================

PATCH_ID="rpi-beta-repos"
PATCH_NAME="Pi Beta-Repositories aktivieren"
PATCH_DESC="Schaltet RPi Beta/Test-Repo frei — aktuellere Kernel, Firmware, Tools"
PATCH_FILE="/etc/apt/sources.list.d/raspi-beta.list"

patch_meta() {
    echo "id:   $PATCH_ID"
    echo "name: $PATCH_NAME"
    echo "desc: $PATCH_DESC"
    echo "file: $PATCH_FILE"
}

patch_check() {
    [ -f "$PATCH_FILE" ] && grep -q "^[^#]" "$PATCH_FILE" 2>/dev/null
}

patch_apply() {
    if patch_check; then
        echo "  Bereits aktiv: $PATCH_NAME"
        return 0
    fi

    sudo tee "$PATCH_FILE" > /dev/null << 'EOF'
deb http://archive.raspberrypi.com/debian/ trixie main beta
# deb http://archive.raspberrypi.com/debian/ trixie main testing
EOF

    sudo apt-get update 2>/dev/null | tail -1

    if patch_check; then
        echo "  OK: Beta-Repository aktiviert"
        echo "       Neue Pakete verfuegbar nach 'apt update'"
        return 0
    else
        echo "  FEHLER: Konnte Repo nicht aktivieren"
        return 1
    fi
}

patch_revert() {
    if ! patch_check; then
        echo "  Patch nicht aktiv: $PATCH_NAME"
        return 0
    fi

    sudo rm -f "$PATCH_FILE"
    sudo apt-get update 2>/dev/null | tail -1

    if ! patch_check; then
        echo "  Revert OK: Beta-Repository entfernt"
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
