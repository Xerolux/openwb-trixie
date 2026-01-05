#!/bin/bash

# OpenWB Virtual Environment Setup Script
# Dieses Script erstellt und verwaltet ein venv für OpenWB
# Das venv überlebt OpenWB-Updates, da es außerhalb des OpenWB-Verzeichnisses liegt

set -e  # Bei Fehlern beenden

# Automatischer Modus für unbeaufsichtigte Aufrufe (z.B. aus Hooks)
OPENWB_VENV_NONINTERACTIVE=${OPENWB_VENV_NONINTERACTIVE:-0}

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfiguration
VENV_DIR="/opt/openwb-venv"
VENV_CONFIG="$VENV_DIR/.openwb-venv-config"
REQUIREMENTS_FILE="$(dirname "$0")/requirements.txt"
VENV_VERSION="1.0.0"

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

# Prüfe ob Python 3.9 installiert ist
check_python() {
    log "Prüfe Python-Installation..."

    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 ist nicht installiert!"
        log_error "Führe zuerst install_python3.9.sh aus"
        exit 1
    fi

    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    log_success "Python $PYTHON_VERSION gefunden"

    # Empfehlung für Python 3.9
    if [[ ! $PYTHON_VERSION =~ ^3\.9\. ]]; then
        log_warning "OpenWB empfiehlt Python 3.9.x, gefunden: $PYTHON_VERSION"
        if [[ "$OPENWB_VENV_NONINTERACTIVE" != "1" ]]; then
            read -p "Trotzdem fortfahren? (j/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Jj]$ ]]; then
                exit 1
            fi
        else
            log_warning "Nicht-interaktiver Modus aktiv – fahre mit System-Python fort"
        fi
    fi
}

# Erstelle venv
create_venv() {
    log "=== Virtual Environment wird erstellt ==="

    # Prüfe ob venv bereits existiert
    if [ -d "$VENV_DIR" ]; then
        log_warning "venv existiert bereits: $VENV_DIR"

        # Lade Config falls vorhanden
        if [ -f "$VENV_CONFIG" ]; then
            source "$VENV_CONFIG"
            log "Existierende venv-Version: ${VENV_VERSION_INSTALLED:-unbekannt}"
        fi

        if [[ "$OPENWB_VENV_NONINTERACTIVE" = "1" ]]; then
            log "Nicht-interaktiver Modus: Überspringe Neuaufbau und aktualisiere bestehendes venv"
            update_venv
            return 0
        else
            read -p "Möchtest du es neu erstellen? (j/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Jj]$ ]]; then
                log_warning "Lösche existierendes venv..."
                sudo rm -rf "$VENV_DIR"
            else
                log "Überspringe venv-Erstellung, führe Update durch..."
                update_venv
                return 0
            fi
        fi
    fi

    # Erstelle Verzeichnis
    log "Erstelle Verzeichnis: $VENV_DIR"
    sudo mkdir -p "$VENV_DIR"

    # Setze Berechtigungen (für User openwb)
    if id "openwb" &>/dev/null; then
        log "Setze Eigentümer auf openwb:openwb"
        sudo chown -R openwb:openwb "$VENV_DIR"
    else
        log_warning "User 'openwb' nicht gefunden, nutze aktuellen User"
        sudo chown -R $USER:$USER "$VENV_DIR"
    fi

    # Erstelle venv (inkl. Systempakete für Hardware-Treiber)
    log "Erstelle Virtual Environment..."
    python3 -m venv --system-site-packages "$VENV_DIR"

    log_success "Virtual Environment erfolgreich erstellt"
}

filter_requirements() {
    local filtered_file="$1"

    # rpi-lgpio wird als Systempaket installiert, um Build-Fehler auf 64-bit-Systemen zu vermeiden
    if grep -q '^rpi-lgpio' "$REQUIREMENTS_FILE"; then
        log "Überspringe rpi-lgpio in pip (wird als Systempaket installiert)"
    fi

    grep -v '^rpi-lgpio' "$REQUIREMENTS_FILE" > "$filtered_file"
}

install_system_rpilgpio() {
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

# Installiere Abhängigkeiten
install_dependencies() {
    log "=== Installiere Python-Abhängigkeiten ==="

    # Stelle Systemabhängigkeiten bereit (für rpi-lgpio)
    install_system_rpilgpio

    # Aktiviere venv
    source "$VENV_DIR/bin/activate"

    # Upgrade pip
    log "Upgrade pip..."
    pip install --upgrade pip

    # Prüfe ob requirements.txt existiert
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        log_error "requirements.txt nicht gefunden: $REQUIREMENTS_FILE"
        exit 1
    fi

    local filtered_requirements
    filtered_requirements=$(mktemp)
    filter_requirements "$filtered_requirements"

    # Installiere Requirements (ohne rpi-lgpio)
    log "Installiere Pakete aus requirements.txt..."
    pip install -r "$filtered_requirements"

    # Speichere installierte Pakete
    log "Speichere installierte Pakete..."
    pip freeze > "$VENV_DIR/installed_requirements.txt"

    # Dokumentiere Systempaket in der Liste
    if dpkg -s python3-rpi-lgpio >/dev/null 2>&1; then
        echo "rpi-lgpio (Systempaket python3-rpi-lgpio)" >> "$VENV_DIR/installed_requirements.txt"
    fi

    # Kopiere requirements.txt für Vergleiche
    cp "$REQUIREMENTS_FILE" "$VENV_DIR/requirements.txt"

    rm -f "$filtered_requirements"
    deactivate
    log_success "Abhängigkeiten erfolgreich installiert"
}

# Erstelle Config-Datei
create_config() {
    log "Erstelle venv-Konfiguration..."

    cat > "$VENV_CONFIG" << EOF
# OpenWB venv Configuration
# Diese Datei wird automatisch generiert
VENV_VERSION_INSTALLED="$VENV_VERSION"
VENV_CREATED="$(date +'%Y-%m-%d %H:%M:%S')"
VENV_PYTHON_VERSION="$(python3 --version 2>&1 | awk '{print $2}')"
VENV_DIR="$VENV_DIR"
EOF

    log_success "Konfiguration erstellt: $VENV_CONFIG"
}

# Update venv
update_venv() {
    log "=== Update Virtual Environment ==="

    if [ ! -d "$VENV_DIR" ]; then
        log_error "venv existiert nicht: $VENV_DIR"
        log "Erstelle venv zuerst..."
        create_venv
        install_dependencies
        create_config
        return 0
    fi

    # Stelle Systemabhängigkeiten bereit (für rpi-lgpio)
    install_system_rpilgpio

    # Aktiviere venv
    source "$VENV_DIR/bin/activate"

    # Upgrade pip
    log "Upgrade pip..."
    pip install --upgrade pip

    local filtered_requirements
    filtered_requirements=$(mktemp)
    filter_requirements "$filtered_requirements"

    # Prüfe ob requirements.txt sich geändert hat
    if [ -f "$VENV_DIR/requirements.txt" ]; then
        if ! diff -q "$REQUIREMENTS_FILE" "$VENV_DIR/requirements.txt" &>/dev/null; then
            log_warning "requirements.txt hat sich geändert"
            log "Installiere neue Abhängigkeiten..."
            pip install -r "$filtered_requirements"
        else
            log "requirements.txt unverändert, upgrade existierende Pakete..."
            pip install --upgrade -r "$filtered_requirements"
        fi
    else
        log "Keine vorherige requirements.txt gefunden, installiere alle..."
        pip install -r "$filtered_requirements"
    fi

    # Speichere neue Version
    pip freeze > "$VENV_DIR/installed_requirements.txt"
    if dpkg -s python3-rpi-lgpio >/dev/null 2>&1; then
        echo "rpi-lgpio (Systempaket python3-rpi-lgpio)" >> "$VENV_DIR/installed_requirements.txt"
    fi
    cp "$REQUIREMENTS_FILE" "$VENV_DIR/requirements.txt"

    rm -f "$filtered_requirements"
    deactivate
    log_success "venv erfolgreich aktualisiert"
}

# Erstelle Wrapper-Skript
create_wrapper() {
    log "=== Erstelle Wrapper-Skript ==="

    local wrapper="/usr/local/bin/openwb-activate"

    sudo tee "$wrapper" > /dev/null << 'EOF'
#!/bin/bash
# OpenWB venv Aktivierungs-Wrapper
# Verwendung: openwb-activate [command]
# Beispiel: openwb-activate python script.py
# Oder source direkt: source openwb-activate

VENV_DIR="/opt/openwb-venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "Fehler: OpenWB venv nicht gefunden: $VENV_DIR"
    echo "Führe setup_venv.sh aus, um es zu erstellen"
    exit 1
fi

# Aktiviere venv
source "$VENV_DIR/bin/activate"

# Wenn Argumente übergeben wurden, führe Befehl aus
if [ $# -gt 0 ]; then
    "$@"
    exit $?
else
    # Keine Argumente: Zeige Info und starte Shell
    echo "OpenWB Virtual Environment aktiviert"
    echo "venv: $VENV_DIR"
    echo "Python: $(python --version)"
    echo ""
    echo "Zum Deaktivieren: deactivate"
    exec $SHELL
fi
EOF

    sudo chmod +x "$wrapper"
    log_success "Wrapper erstellt: $wrapper"
    log "Verwendung: openwb-activate [command]"
}

# Erstelle Systemd-Service-Ergänzungen
create_systemd_helper() {
    log "=== Erstelle systemd Service-Helper ==="

    local helper="/opt/openwb-venv/systemd-environment"

    cat > "$helper" << EOF
# OpenWB venv Environment für systemd Services
# Füge diese Datei zu deinen systemd Services hinzu:
# [Service]
# EnvironmentFile=/opt/openwb-venv/systemd-environment

PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin
VIRTUAL_ENV=$VENV_DIR
PYTHONHOME=
EOF

    log_success "systemd Helper erstellt: $helper"
    log "Füge 'EnvironmentFile=$helper' zu deinen OpenWB systemd Services hinzu"
}

# Zeige Informationen
show_info() {
    echo ""
    echo "====================================================================="
    echo "   OpenWB Virtual Environment erfolgreich eingerichtet!"
    echo "====================================================================="
    echo ""
    echo "venv-Verzeichnis: $VENV_DIR"
    echo "Python-Version: $(python3 --version)"
    echo ""
    echo "Verwendung:"
    echo "  1. Manuell aktivieren:"
    echo "     source $VENV_DIR/bin/activate"
    echo ""
    echo "  2. Mit Wrapper-Skript:"
    echo "     openwb-activate python script.py"
    echo ""
    echo "  3. In systemd Services:"
    echo "     EnvironmentFile=/opt/openwb-venv/systemd-environment"
    echo ""
    echo "  4. venv aktualisieren:"
    echo "     ./setup_venv.sh --update"
    echo ""
    echo "Installierte Pakete:"
    source "$VENV_DIR/bin/activate"
    pip list
    deactivate
    echo ""
    echo "====================================================================="
}

# Hauptfunktion
main() {
    echo "====================================================================="
    echo "   OpenWB Virtual Environment Setup"
    echo "====================================================================="
    echo ""

    # Parse Argumente
    case "${1:-}" in
        --update|-u)
            log "Update-Modus aktiviert"
            check_python
            update_venv
            log_success "Update abgeschlossen"
            exit 0
            ;;
        --help|-h)
            echo "Verwendung: $0 [OPTION]"
            echo ""
            echo "Optionen:"
            echo "  (keine)      Erstelle neues venv"
            echo "  --update     Update existierendes venv"
            echo "  --help       Zeige diese Hilfe"
            exit 0
            ;;
    esac

    # Normaler Installations-Modus
    check_python
    create_venv
    install_dependencies
    create_config
    create_wrapper
    create_systemd_helper
    show_info

    log_success "=== Installation abgeschlossen! ==="
}

# Fehlerbehandlung
trap 'log_error "Fehler in Zeile $LINENO"' ERR

# Script ausführen
main "$@"
