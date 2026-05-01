#!/bin/bash
# ============================================================================
# Patch: Log-Rotation
# ============================================================================
# Id: log-rotation
# Name: Log-Rotation fuer OpenWB
# Desc: Erstellt eine logrotate-Konfiguration fuer OpenWB Logs in der ramdisk.
#       Verhindert endlos wachsende Logdateien.
# File: /etc/logrotate.d/openwb
# ============================================================================

PATCH_ID="log-rotation"
PATCH_NAME="Log-Rotation fuer OpenWB"
PATCH_DESC="Dreht OpenWB Logs taeglich, behaelt 3 Tage, komprimiert alte"
PATCH_FILE="/etc/logrotate.d/openwb"

LOGROTATE_CONF="/etc/logrotate.d/openwb"
OPENWB_RAMDISK="${OPENWB_DIR:-/var/www/html/openWB}/ramdisk"

patch_meta() {
    echo "id:   $PATCH_ID"
    echo "name: $PATCH_NAME"
    echo "desc: $PATCH_DESC"
    echo "file: $PATCH_FILE"
}

patch_check() {
    [ -f "$LOGROTATE_CONF" ]
}

patch_apply() {
    if patch_check; then
        echo "  Bereits gepatcht: $PATCH_NAME"
        return 0
    fi

    sudo tee "$LOGROTATE_CONF" > /dev/null << 'LOGEOF'
/var/www/html/openWB/ramdisk/*.log {
    daily
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    maxsize 10M
}
LOGEOF

    if patch_check; then
        echo "  OK: $PATCH_NAME angewendet ($LOGROTATE_CONF erstellt)"
        return 0
    else
        echo "  FEHLER: Konnte $LOGROTATE_CONF nicht erstellen"
        return 1
    fi
}

patch_revert() {
    if ! patch_check; then
        echo "  Patch nicht aktiv: $PATCH_NAME"
        return 0
    fi

    sudo rm -f "$LOGROTATE_CONF"

    if ! patch_check; then
        echo "  Revert OK: $PATCH_NAME ($LOGROTATE_CONF entfernt)"
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
