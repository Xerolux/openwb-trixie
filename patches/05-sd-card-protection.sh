#!/bin/bash
# ============================================================================
# Patch: SD-Kartenschutz
# ============================================================================
# Id: sd-card-protection
# Name: SD-Kartenschutz (Schreibzugriffe minimieren)
# Desc: Mountet /var/log als tmpfs, setzt noatime auf Root-FS,
#       konfiguriert journald auf volatile Speicherung.
#       Reduziert SD-Karten-Verschleiss deutlich.
# File: /etc/fstab + /etc/systemd/journald.conf
# ============================================================================

PATCH_ID="sd-card-protection"
PATCH_NAME="SD-Kartenschutz"
PATCH_DESC="tmpfs fuer /var/log, noatime, journald volatile — reduziert SD-Verschleiss"
PATCH_FILE="/etc/fstab"

patch_meta() {
    echo "id:   $PATCH_ID"
    echo "name: $PATCH_NAME"
    echo "desc: $PATCH_DESC"
    echo "file: $PATCH_FILE"
}

patch_check() {
    grep -q "tmpfs.*\/var\/log" /etc/fstab 2>/dev/null
}

patch_apply() {
    if patch_check; then
        echo "  Bereits aktiv: $PATCH_NAME"
        return 0
    fi

    # Backup
    sudo cp /etc/fstab /etc/fstab.pre-sd-card-protection.$(date +%Y%m%d%H%M%S)

    # 1. /var/log als tmpfs (50MB)
    if ! grep -q "tmpfs.*\/var\/log" /etc/fstab 2>/dev/null; then
        echo "tmpfs /var/log tmpfs defaults,noatime,nosuid,mode=0755,size=50m 0 0" | sudo tee -a /etc/fstab > /dev/null
    fi

    # 2. noatime auf Root-FS
    if ! awk '$2=="/"' /etc/fstab | grep -q "noatime" 2>/dev/null; then
        sudo sed -i '/[[:space:]]\/[[:space:]]/s/defaults/defaults,noatime/' /etc/fstab
        sudo sed -i '/[[:space:]]\/[[:space:]]/s/relatime/noatime/' /etc/fstab
    fi

    # 3. journald auf volatile (nur im RAM)
    if [ -f /etc/systemd/journald.conf ]; then
        sudo sed -i 's/^#*Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
        sudo sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=20M/' /etc/systemd/journald.conf
        sudo systemctl restart systemd-journald 2>/dev/null || true
    fi

    # 4. /var/log mounten + wichtige Verzeichnisse erstellen
    sudo mkdir -p /var/log.backup
    sudo rsync -a /var/log/ /var/log.backup/ 2>/dev/null || true
    sudo mount /var/log 2>/dev/null || true
    sudo mkdir -p /var/log/openWB /var/log/apache2 /var/log/ntpstats
    sudo cp -a /var/log.backup/* /var/log/ 2>/dev/null || true

    # 5. Boot-Script das Logs aus Backup restored
    if [ ! -f /etc/rc.local ] || ! grep -q "sd-card-protection" /etc/rc.local 2>/dev/null; then
        sudo tee /etc/rc.local > /dev/null << 'RCEOF'
#!/bin/bash
# openwb-trixie: sd-card-protection — restore log dirs on boot
mkdir -p /var/log/openWB /var/log/apache2 /var/log/ntpstats
exit 0
RCEOF
        sudo chmod +x /etc/rc.local
    fi

    if patch_check; then
        echo "  OK: $PATCH_NAME aktiviert"
        echo "       /var/log → tmpfs (50MB)"
        echo "       Root-FS → noatime"
        echo "       journald → volatile"
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

    # tmpfs unmounten
    sudo umount /var/log 2>/dev/null || true

    # fstab bereinigen
    sudo sed -i '/tmpfs.*\/var\/log/d' /etc/fstab

    # Logs zurueckkopieren
    sudo rsync -a /var/log.backup/ /var/log/ 2>/dev/null || true
    sudo rm -rf /var/log.backup

    # noatime entfernen
    sudo sed -i 's/defaults,noatime/defaults/' /etc/fstab
    sudo sed -i 's/noatime/relatime/' /etc/fstab

    # journald zuruecksetzen
    if [ -f /etc/systemd/journald.conf ]; then
        sudo sed -i 's/^Storage=volatile/#Storage=auto/' /etc/systemd/journald.conf
        sudo sed -i 's/^SystemMaxUse=20M/#SystemMaxUse=/' /etc/systemd/journald.conf
        sudo systemctl restart systemd-journald 2>/dev/null || true
    fi

    # rc.local entfernen
    sudo rm -f /etc/rc.local

    if ! patch_check; then
        echo "  Revert OK: $PATCH_NAME (SD-Schutz entfernt)"
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
