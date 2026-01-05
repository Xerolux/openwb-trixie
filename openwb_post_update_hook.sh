#!/bin/bash

# OpenWB Post-Update Hook
# Dieses Script wird nach OpenWB-Updates ausgeführt, um das venv zu aktualisieren
# Installation: Kopiere dieses Script nach /var/www/html/openWB/data/config/post-update.sh
#               oder verlinke es entsprechend in das OpenWB-Update-System

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[OpenWB-Hook]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OpenWB-Hook] ✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[OpenWB-Hook] ⚠${NC} $1"
}

log_error() {
    echo -e "${RED}[OpenWB-Hook] ✗${NC} $1"
}

# Konfiguration
VENV_DIR="/opt/openwb-venv"
SETUP_SCRIPT="/home/openwb/openwb-trixie/setup_venv.sh"
REQUIREMENTS_FILE="/home/openwb/openwb-trixie/requirements.txt"

install_system_rpilgpio() {
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        return
    fi

    if ! grep -q '^rpi-lgpio' "$REQUIREMENTS_FILE"; then
        return
    fi

    log "Stelle Systempaket python3-rpi-lgpio bereit..."

    if dpkg -s python3-rpi-lgpio >/dev/null 2>&1; then
        log "python3-rpi-lgpio bereits installiert"
    else
        sudo apt-get update
        sudo apt-get install -y python3-rpi-lgpio
    fi
}

filter_requirements() {
    local filtered_file="$1"

    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        return 1
    fi

    if grep -q '^rpi-lgpio' "$REQUIREMENTS_FILE"; then
        log "Überspringe rpi-lgpio in pip (wird als Systempaket installiert)"
    fi

    grep -v '^rpi-lgpio' "$REQUIREMENTS_FILE" > "$filtered_file"
}

log "=== OpenWB Post-Update Hook gestartet ==="

# Prüfe ob venv existiert
if [ ! -d "$VENV_DIR" ]; then
    log_warning "venv nicht gefunden: $VENV_DIR"
    log "venv scheint nicht installiert zu sein"
    log "Überspringe venv-Update"
    exit 0
fi

# Prüfe ob Setup-Script existiert
if [ ! -f "$SETUP_SCRIPT" ]; then
    log_warning "Setup-Script nicht gefunden: $SETUP_SCRIPT"
    log "Versuche manuelles venv-Update..."

    # Versuche Update mit vorhandenen Tools
    if [ -f "$REQUIREMENTS_FILE" ]; then
        install_system_rpilgpio

        local filtered_requirements
        filtered_requirements=$(mktemp)

        if ! filter_requirements "$filtered_requirements"; then
            log_error "Konnte gefilterte requirements nicht erstellen"
            exit 1
        fi

        log "Aktiviere venv und aktualisiere Pakete..."
        source "$VENV_DIR/bin/activate"
        pip install --upgrade pip
        pip install --upgrade -r "$filtered_requirements"
        pip freeze > "$VENV_DIR/installed_requirements.txt"
        if dpkg -s python3-rpi-lgpio >/dev/null 2>&1; then
            echo "rpi-lgpio (Systempaket python3-rpi-lgpio)" >> "$VENV_DIR/installed_requirements.txt"
        fi
        deactivate

        rm -f "$filtered_requirements"

        log_success "venv manuell aktualisiert"
    else
        log_error "requirements.txt nicht gefunden, kann venv nicht aktualisieren"
        exit 1
    fi
else
    # Führe Setup-Script im Update-Modus aus
    log "Führe venv-Update aus..."
    OPENWB_VENV_NONINTERACTIVE=1 bash "$SETUP_SCRIPT" --update

    if [ $? -eq 0 ]; then
        log_success "venv erfolgreich aktualisiert"
    else
        log_error "Fehler beim venv-Update"
        exit 1
    fi
fi

# Optional: Prüfe OpenWB-Services und starte neu
if command -v systemctl &> /dev/null; then
    log "Prüfe OpenWB-Services..."

    # Liste der möglichen OpenWB-Services
    SERVICES=("openwb" "openwb.service" "openwb2" "openwb2.service")

    for service in "${SERVICES[@]}"; do
        if systemctl list-units --full -all | grep -q "$service"; then
            log "Starte $service neu..."
            sudo systemctl restart "$service" || log_warning "Konnte $service nicht neustarten"
        fi
    done
fi

log_success "=== Post-Update Hook abgeschlossen ==="
exit 0
