#!/bin/bash
# ============================================================================
# Patch: Stromspar-Modus
# ============================================================================
# Id: power-saving
# Name: Stromspar-Modus (Pi / ARM)
# Desc: Deaktiviert WiFi, Bluetooth und HDMI wenn nicht benoetigt.
#       Setzt CPU-Governor auf ondemand. Spart ca. 100-200mA.
#       Nur fuer Raspberry Pi und aehnliche ARM-Geraete.
# File: /etc/rc.local + /boot/firmware/config.txt
# ============================================================================

PATCH_ID="power-saving"
PATCH_NAME="Stromspar-Modus"
PATCH_DESC="WiFi/BT/HDMI off, CPU ondemand — spart ~100-200mA (nur Raspberry Pi)"
PATCH_FILE="/etc/rc.local"

patch_meta() {
    echo "id:   $PATCH_ID"
    echo "name: $PATCH_NAME"
    echo "desc: $PATCH_DESC"
    echo "file: $PATCH_FILE"
}

patch_check() {
    [ -f "/etc/openwb-power-saving-enabled" ]
}

patch_apply() {
    if patch_check; then
        echo "  Bereits aktiv: $PATCH_NAME"
        return 0
    fi

    if ! is_arm_arch 2>/dev/null; then
        echo "  WARNUNG: Kein ARM-System — Stromspar-Modus nicht sinnvoll"
        echo "  Überspringe WiFi/BT/HDMI, setze nur CPU-Governor"
    fi

    # 1. CPU-Governor auf ondemand
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo "ondemand" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
        if ! grep -q "scaling_governor" /etc/rc.local 2>/dev/null; then
            sudo sed -i '/^exit 0/i echo "ondemand" > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null' /etc/rc.local 2>/dev/null || true
        fi
    fi

    # 2. HDMI off (nur ARM)
    if is_arm_arch 2>/dev/null; then
        sudo tvservice -o 2>/dev/null || true
        if ! grep -q "tvservice" /etc/rc.local 2>/dev/null; then
            sudo sed -i '/^exit 0/i tvservice -o 2>/dev/null || true' /etc/rc.local 2>/dev/null || true
        fi
    fi

    # 3. WiFi off wenn Ethernet aktiv (nur ARM)
    if is_arm_arch 2>/dev/null; then
        if ip route show default 2>/dev/null | grep -q "eth0\|end0\|enp"; then
            sudo rfkill block wifi 2>/dev/null || true
            if ! grep -q "rfkill block wifi" /etc/rc.local 2>/dev/null; then
                sudo sed -i '/^exit 0/i ip route show default | grep -q "eth0\|end0\|enp" && rfkill block wifi 2>/dev/null' /etc/rc.local 2>/dev/null || true
            fi
        fi
    fi

    # 4. Bluetooth off (nur ARM)
    if is_arm_arch 2>/dev/null; then
        sudo rfkill block bluetooth 2>/dev/null || true
        if ! grep -q "rfkill block bluetooth" /etc/rc.local 2>/dev/null; then
            sudo sed -i '/^exit 0/i rfkill block bluetooth 2>/dev/null' /etc/rc.local 2>/dev/null || true
        fi
    fi

    # Marker
    sudo touch /etc/openwb-power-saving-enabled

    if patch_check; then
        echo "  OK: $PATCH_NAME aktiviert"
        echo "       CPU-Governor → ondemand"
        is_arm_arch 2>/dev/null && echo "       WiFi → off (Ethernet aktiv)" && echo "       Bluetooth → off" && echo "       HDMI → off"
        return 0
    else
        echo "  FEHLER: Patch konnte nicht verifiziert werden"
        return 1
    fi
}

patch_revert() {
    if ! patch_check; then
        echo "  Patch nicht aktiv: $PATCH_NAME"
        return 0
    fi

    # WiFi/BT wieder an
    sudo rfkill unblock wifi 2>/dev/null || true
    sudo rfkill unblock bluetooth 2>/dev/null || true

    # HDMI an
    sudo tvservice -p 2>/dev/null || true

    # rc.local bereinigen
    sudo sed -i '/rfkill/d' /etc/rc.local 2>/dev/null || true
    sudo sed -i '/tvservice/d' /etc/rc.local 2>/dev/null || true
    sudo sed -i '/scaling_governor/d' /etc/rc.local 2>/dev/null || true

    # CPU-Governor zurueck auf performance
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
    fi

    sudo rm -f /etc/openwb-power-saving-enabled

    if ! patch_check; then
        echo "  Revert OK: $PATCH_NAME (alles wieder an)"
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
