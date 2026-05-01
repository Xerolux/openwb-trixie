#!/bin/bash
# ============================================================================
# Patch: Swap einrichten
# ============================================================================
# Id: swap-file
# Name: Swap einrichten (zram auf Pi, Datei auf ARM/x86)
# Desc: Raspberry Pi: installiert rpi-swap (zram-basiert, SD-schonend).
#       Andere Systeme: erstellt 2GB Swap-Datei mit swappiness=10.
# File: /swapfile bzw. rpi-swap Paket
# Arch: arm
# ============================================================================

PATCH_ID="swap-file"
PATCH_NAME="Swap einrichten"
PATCH_DESC="Pi: rpi-swap (zram). Andere: 2GB Swap-Datei. Reduziert RAM-Probleme."
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
    if is_raspberry_pi 2>/dev/null && dpkg -s rpi-swap >/dev/null 2>&1; then
        return 0
    fi
    swapon --show=NAME --noheadings 2>/dev/null | grep -q "^${SWAPFILE}$"
}

patch_apply() {
    if patch_check; then
        echo "  Bereits aktiv: $PATCH_NAME"
        return 0
    fi

    if is_raspberry_pi 2>/dev/null; then
        echo "  Raspberry Pi erkannt — installiere rpi-swap (zram)..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y rpi-swap 2>/dev/null
        if dpkg -s rpi-swap >/dev/null 2>&1; then
            echo "  OK: rpi-swap installiert (zram-basiert, aktiv nach Reboot)"
            return 0
        else
            echo "  WARNUNG: rpi-swap nicht verfügbar, falle auf Swap-Datei zurück..."
        fi
    fi

    # Fallback: manuelle Swap-Datei
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
        echo "  OK: Swap aktiviert ($(free -h | awk '/Swap/{print $2}') total)"
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

    if dpkg -s rpi-swap >/dev/null 2>&1; then
        echo "  Entferne rpi-swap..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y rpi-swap 2>/dev/null
    fi

    sudo swapoff "$SWAPFILE" 2>/dev/null || true
    sudo sed -i "\|^${SWAPFILE}|d" /etc/fstab
    sudo rm -f "$SWAPFILE"
    sudo sed -i "/^vm.swappiness=10/d" /etc/sysctl.conf

    if ! patch_check; then
        echo "  Revert OK: Swap entfernt"
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
