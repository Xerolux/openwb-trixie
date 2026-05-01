#!/bin/bash
# ============================================================================
# Patch: Swap-Datei erstellen
# ============================================================================
# Id: swap-file
# Name: 2GB Swap-Datei erstellen
# Desc: Erstellt eine 2GB Swap-Datei fuer Systeme mit wenig RAM (Pi, VMs).
#       Aktiviert sie permanent und setzt swappiness auf 10 (nur bei Notfall).
# File: /swapfile
# ============================================================================

PATCH_ID="swap-file"
PATCH_NAME="2GB Swap-Datei erstellen"
PATCH_DESC="2GB Swap fuer RAM-schwache Systeme, swappiness=10 (schont SD-Karte)"
PATCH_FILE="/swapfile"

SWAPFILE="/swapfile"
SWAPSIZE="2G"

patch_meta() {
    echo "id:   $PATCH_ID"
    echo "name: $PATCH_NAME"
    echo "desc: $PATCH_DESC"
    echo "file: $PATCH_FILE"
}

patch_check() {
    swapon --show=NAME --noheadings 2>/dev/null | grep -q "^${SWAPFILE}$"
}

patch_apply() {
    if patch_check; then
        echo "  Bereits aktiv: $PATCH_NAME"
        return 0
    fi

    if [ -f "$SWAPFILE" ]; then
        echo "  Swap-Datei existiert bereits, aktiviere..."
        sudo swapoff "$SWAPFILE" 2>/dev/null || true
    else
        echo "  Erstelle ${SWAPSIZE} Swap-Datei..."
        sudo fallocate -l "$SWAPSIZE" "$SWAPFILE" 2>/dev/null || sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=2048 status=progress
        sudo chmod 600 "$SWAPFILE"
        sudo mkswap "$SWAPFILE" >/dev/null
    fi

    sudo swapon "$SWAPFILE"

    if ! grep -q "^${SWAPFILE}" /etc/fstab 2>/dev/null; then
        echo "${SWAPFILE} none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
    fi

    sudo sysctl vm.swappiness=10 2>/dev/null || true
    if ! grep -q "^vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
        echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null
    fi

    if patch_check; then
        echo "  OK: $PATCH_NAME aktiviert ($(free -h | awk '/Swap/{print $2}') Swap)"
        return 0
    else
        echo "  FEHLER: Swap konnte nicht aktiviert werden"
        return 1
    fi
}

patch_revert() {
    if ! patch_check; then
        echo "  Patch nicht aktiv: $PATCH_NAME"
        return 0
    fi

    sudo swapoff "$SWAPFILE" 2>/dev/null || true
    sudo sed -i "\|^${SWAPFILE}|d" /etc/fstab
    sudo rm -f "$SWAPFILE"
    sudo sed -i "/^vm.swappiness=10/d" /etc/sysctl.conf

    if ! patch_check; then
        echo "  Revert OK: $PATCH_NAME (Swap deaktiviert und Datei entfernt)"
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
