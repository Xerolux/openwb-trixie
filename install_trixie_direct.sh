#!/bin/bash

# OpenWB Installation für frische Debian Trixie Systeme
#
# Dieses Script ist optimiert für Systeme die BEREITS Trixie verwenden
# (kein Upgrade von Bookworm nötig)
#
# Nutzt System-Python mit venv - KEINE Python-Kompilierung!
# Spart 30-60 Minuten Installationszeit!

set -e  # Script bei Fehlern beenden

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging-Funktionen
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
}

echo "====================================================================="
echo "   OpenWB Installation für Debian Trixie"
echo "====================================================================="
echo ""
echo "Dieses Script installiert OpenWB auf einem FRISCHEN Trixie-System"
echo ""
echo "Was wird gemacht:"
echo "  1. System aktualisieren"
echo "  2. Build-Abhängigkeiten installieren (SWIG, gcc, etc.)"
echo "  3. Repository vorbereiten"
echo "  4. GPIO-Konfiguration"
echo "  5. PHP konfigurieren"
echo "  6. Virtual Environment mit System-Python (schnell!)"
echo "  7. OpenWB Installation"
echo "  8. Post-Update Hook einrichten"
echo ""
echo "Vorteile:"
echo "  ✓ Keine Python-Kompilierung (spart 30-60 Min!)"
echo "  ✓ Nutzt modernes Debian Trixie Python (3.12+)"
echo "  ✓ Isolierte Paket-Installation (venv)"
echo "  ✓ Überlebt OpenWB-Updates automatisch"
echo ""

# Prüfe ob bereits Trixie läuft
if ! grep -q "trixie" /etc/debian_version 2>/dev/null && ! lsb_release -c 2>/dev/null | grep -q "trixie"; then
    log_error "Dieses System läuft NICHT auf Debian Trixie!"
    echo ""
    echo "Optionen:"
    echo "  1. Nutze install_complete.sh für Upgrade von Bookworm zu Trixie"
    echo "  2. Führe zuerst update_to_trixie.sh aus"
    exit 1
fi

log_success "Debian Trixie erkannt"

read -p "Möchtest du fortfahren? (j/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Installation abgebrochen."
    exit 1
fi

# Schritt 1: System aktualisieren
log "=== Schritt 1: System aktualisieren ==="
sudo apt update
sudo apt upgrade -y

# Schritt 2: Build-Abhängigkeiten installieren
log "=== Schritt 2: Build-Abhängigkeiten installieren ==="
log "Installiere SWIG und Entwicklungs-Tools für Python-Pakete..."
sudo apt install -y \
    swig \
    build-essential \
    python3-dev \
    python3-pip \
    python3-rpi-lgpio \
    pkg-config \
    liblgpio-dev \
    libgpiod-dev \
    libffi-dev
log_success "Build-Abhängigkeiten erfolgreich installiert"

# Schritt 3: Git installieren und Repository klonen (falls nicht vorhanden)
log "=== Schritt 3: Repository vorbereiten ==="

if [ ! -d "/home/openwb/openwb-trixie" ]; then
    log "Git installieren..."
    sudo apt install git -y

    log "Repository klonen..."
    cd /home/openwb 2>/dev/null || cd ~
    git clone https://github.com/Xerolux/openwb-trixie.git
    cd openwb-trixie
else
    log "Repository bereits vorhanden"
    cd /home/openwb/openwb-trixie
fi

# Schritt 4: GPIO-Konfiguration
log "=== Schritt 4: GPIO-Konfiguration ==="

log "Konfiguriere /boot/firmware/config.txt für OpenWB..."
sudo cp /boot/firmware/config.txt /boot/firmware/config.txt.backup.$(date +%Y%m%d_%H%M%S)

# Audio deaktivieren
sudo sed -i 's/dtparam=audio=on/dtparam=audio=off/g' /boot/firmware/config.txt

# vc4-kms-v3d auskommentieren
sudo sed -i 's/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/g' /boot/firmware/config.txt

# OpenWB Konfiguration hinzufügen (falls noch nicht vorhanden)
if ! grep -q "# openwb - begin" /boot/firmware/config.txt; then
    log "Füge OpenWB-Konfiguration hinzu..."
    sudo tee -a /boot/firmware/config.txt > /dev/null << 'EOF'
# openwb - begin
# openwb-version:4
# Do not edit this section! We need begin/end and version for proper updates!
[all]
gpio=4,5,7,11,17,22,23,24,25,26,27=op,dl
gpio=6,8,9,10,12,13,16,21=ip,pu
[cm4]
# GPIO 22 is the buzzer on computemodule4
gpio=22=op,dh
[all]
# enable uart for modbus port on older addon hat
# this also requires to disable Bluetooth
dtoverlay=disable-bt
enable_uart=1
avoid_warnings=1
# openwb - end
EOF
    log_success "GPIO-Konfiguration hinzugefügt"
else
    log "GPIO-Konfiguration bereits vorhanden"
fi

# Schritt 5: PHP Upload-Limits konfigurieren
log "=== Schritt 5: PHP konfigurieren ==="
sudo mkdir -p /etc/php/8.4/apache2/conf.d/ 2>/dev/null || true
echo "upload_max_filesize = 300M" | sudo tee /etc/php/8.4/apache2/conf.d/20-uploadlimit.ini > /dev/null
echo "post_max_size = 300M" | sudo tee -a /etc/php/8.4/apache2/conf.d/20-uploadlimit.ini > /dev/null
log_success "PHP Upload-Limits auf 300M gesetzt"

# Schritt 6: Virtual Environment erstellen
log "=== Schritt 6: Virtual Environment Setup ==="
log "Nutzt System-Python - KEINE Kompilierung nötig!"

chmod +x install_python3.9.sh
# Non-interaktiver venv-Setup ohne Rückfragen
OPENWB_VENV_NONINTERACTIVE=1 ./install_python3.9.sh --venv-only

if [ $? -ne 0 ]; then
    log_error "Fehler beim venv-Setup"
    exit 1
fi

log_success "Virtual Environment erfolgreich erstellt"

# Schritt 7: OpenWB Installation
log "=== Schritt 7: OpenWB Installation ==="

# Prüfe ob OpenWB bereits installiert ist
if [ -f "/var/www/html/openWB/openwb.sh" ] || [ -f "/home/openwb/openwb/openwb.sh" ]; then
    log "OpenWB bereits installiert, überspringe..."
else
    log "OpenWB wird installiert..."
    curl -s https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh | sudo bash
    log_success "OpenWB erfolgreich installiert"
fi

# Schritt 8: Post-Update Hook installieren
log "=== Schritt 8: Post-Update Hook einrichten ==="

if [ -f "openwb_post_update_hook.sh" ]; then
    OPENWB_DIRS=(
        "/var/www/html/openWB"
        "/home/openwb/openWB"
        "/opt/openWB"
    )

    for openwb_dir in "${OPENWB_DIRS[@]}"; do
        if [ -d "$openwb_dir" ]; then
            sudo mkdir -p "$openwb_dir/data/config"
            sudo cp openwb_post_update_hook.sh "$openwb_dir/data/config/post-update.sh"
            sudo chmod +x "$openwb_dir/data/config/post-update.sh"
            log_success "Post-Update Hook installiert: $openwb_dir/data/config/post-update.sh"
            break
        fi
    done
fi

# Finale Prüfung
log "=== Finale Überprüfung ==="

# System-Python prüfen
SYSTEM_PYTHON=$(python3 --version 2>/dev/null || echo "Fehler")
log "System Python: $SYSTEM_PYTHON"

# venv-Python prüfen
if [ -d "/opt/openwb-venv" ]; then
    source /opt/openwb-venv/bin/activate
    VENV_PYTHON=$(python --version 2>/dev/null || echo "Fehler")
    deactivate
    log "venv Python: $VENV_PYTHON"
fi

# Trixie-Version prüfen
TRIXIE_VERSION=$(lsb_release -c 2>/dev/null | awk '{print $2}' || cat /etc/debian_version)
log "Debian Version: $TRIXIE_VERSION"

echo ""
echo "====================================================================="
echo "   Installation abgeschlossen!"
echo "====================================================================="
echo ""
echo "Zusammenfassung:"
echo "  ✓ Debian Trixie: $TRIXIE_VERSION"
echo "  ✓ System Python: $SYSTEM_PYTHON"
echo "  ✓ venv Python: ${VENV_PYTHON:-nicht installiert}"
echo "  ✓ Virtual Environment: /opt/openwb-venv"
echo "  ✓ Post-Update Hook: installiert"
echo ""
echo "Nächste Schritte:"
echo "  1. Neustart empfohlen für GPIO-Konfiguration:"
echo "     sudo reboot"
echo ""
echo "  2. Nach Neustart - OpenWB Web-Interface öffnen:"
echo "     http://$(hostname -I | awk '{print $1}')"
echo ""
echo "  3. Python-Skripte mit venv ausführen:"
echo "     openwb-activate python script.py"
echo ""
echo "Vorteile dieser Installation:"
echo "  ✓ Keine Python-Kompilierung (30-60 Min gespart!)"
echo "  ✓ Nutzt modernes Trixie-Python (${SYSTEM_PYTHON})"
echo "  ✓ venv überlebt OpenWB-Updates automatisch"
echo "  ✓ Automatische venv-Updates nach OpenWB-Updates"
echo ""
echo "====================================================================="

log_warning "Ein Neustart wird empfohlen für GPIO-Konfiguration!"
read -p "Jetzt neustarten? (j/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    sudo reboot
fi
