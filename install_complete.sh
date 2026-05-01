#!/bin/bash

# OpenWB Trixie - Komplette Installation
# Dieses Script führt alle notwendigen Schritte automatisch durch:
# 1. Repository klonen
# 2. Update auf Debian Trixie
# 3. Python 3.9.23 Installation
# 4. OpenWB Installation
# 5. Automatische Neustarts
#
# Optionen:
#   --with-venv    Installiert Python mit isoliertem venv (empfohlen)
#   --help         Zeigt diese Hilfe

set -Ee -o pipefail  # Script bei Fehlern beenden

# Parse Argumente
USE_VENV=false
CONTINUE_STEP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --with-venv)
            USE_VENV=true
            shift
            ;;
        --continue)
            # Wird intern für Fortsetzung nach Neustart verwendet
            shift
            CONTINUE_STEP="${1:-}"
            shift
            ;;
        --help|-h)
            echo "OpenWB Trixie - Komplette Installation"
            echo ""
            echo "Verwendung: $0 [OPTIONEN]"
            echo ""
            echo "Optionen:"
            echo "  (keine)         Standard-Installation"
            echo "  --with-venv     Mit isoliertem Virtual Environment (empfohlen)"
            echo "  --help          Zeigt diese Hilfe"
            echo ""
            echo "Mit --with-venv werden Python-Pakete isoliert installiert"
            echo "und überleben OpenWB-Updates"
            exit 0
            ;;
        *)
            # Unbekannte Argumente ignorieren
            shift
            ;;
    esac
done

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging-Funktion
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

on_error() {
    local exit_code="$1"
    local line_no="$2"
    local cmd="$3"
    log_error "Fehler in Zeile $line_no: $cmd (Exit-Code: $exit_code)"
    log_error "Tipp: Bei Python/PEP668-Problemen '--with-venv' nutzen und openwb2 auf venv prüfen."
}

trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

configure_openwb_venv_runtime() {
    local openwb_dir="$1"
    local venv_python="/opt/openwb-venv/bin/python3"
    local venv_pip="/opt/openwb-venv/bin/pip3"
    local service_file="$openwb_dir/data/config/openwb2.service"
    local remote_service_file="/etc/systemd/system/openwbRemoteSupport.service"
    local atreboot_file="$openwb_dir/runs/atreboot.sh"

    if [ ! -d "$openwb_dir" ]; then
        return 0
    fi

    if [ ! -x "$venv_python" ] || [ ! -x "$venv_pip" ]; then
        log_warning "venv-Python/Pip nicht gefunden, überspringe Runtime-Anpassungen"
        return 0
    fi

    # Services stoppen vor dem Patchen (verhindert Race Conditions)
    for svc in openwb2 openwb; do
        if systemctl is-active "$svc" &>/dev/null; then
            sudo systemctl stop "$svc" \
                && log "Gestoppt: $svc" \
                || log_warning "Konnte $svc nicht stoppen (wird ignoriert)"
        fi
    done

    if [ -f "$service_file" ]; then
        log "Passe openwb2.service auf venv-Python an..."
        sudo sed -i "s#^ExecStart=.*#ExecStart=$venv_python $openwb_dir/packages/main.py#g" "$service_file"
    fi

    if [ -f "$atreboot_file" ]; then
        log "Passe atreboot.sh auf venv-pip an (PEP668-sicher)..."
        sudo sed -i "s#\\([^[:alnum:]_/.-]\\|^\\)pip3 install -r#\\1$venv_pip install -r#g" "$atreboot_file"
    fi

    if [ -f "$remote_service_file" ]; then
        log "Passe openwbRemoteSupport.service auf venv-Python an..."
        sudo sed -i "s#^ExecStart=.*#ExecStart=$venv_python $openwb_dir/runs/remoteSupport/remoteSupport.py#g" "$remote_service_file"
    fi

    sudo systemctl daemon-reload || true

    # Services neu starten nach dem Patchen
    for svc in openwb2 openwb; do
        if systemctl is-enabled "$svc" &>/dev/null; then
            sudo systemctl restart "$svc" \
                && log_success "Neugestartet: $svc" \
                || log_warning "Konnte $svc nicht neustarten"
        fi
    done

    log_success "openWB Runtime auf venv umgestellt"
}

is_trixie() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [ "${VERSION_CODENAME:-}" = "trixie" ] || printf '%s\n' "${VERSION:-}" | grep -qi 'trixie'; then
            return 0
        fi
    fi

    if command -v lsb_release >/dev/null 2>&1 && lsb_release -c 2>/dev/null | grep -q "trixie"; then
        return 0
    fi

    grep -q "trixie" /etc/debian_version 2>/dev/null
}

# Hilfsfunktion für Neustarts
reboot_and_continue() {
    local next_step=$1
    log_warning "Erstelle Fortsetzungsscript für nächsten Schritt: $next_step"
    
    # Save VENV state
    if [ "$USE_VENV" = true ]; then
        echo "--with-venv" > /tmp/openwb_install_args
    else
        echo "" > /tmp/openwb_install_args
    fi

    # Aktuelles Script und Fortschritt speichern
    cat > /tmp/openwb_install_continue.sh << 'EOF'
#!/bin/bash
# Automatische Fortsetzung der OpenWB Installation

# Fortschritt aus Datei lesen
if [ -f /tmp/openwb_install_step ]; then
    STEP=$(cat /tmp/openwb_install_step)
    echo "Fortsetzung ab Schritt: $STEP"
else
    echo "Fehler: Keine Fortschritt-Datei gefunden"
    exit 1
fi

ARGS="--continue $STEP"
if [ -f /tmp/openwb_install_args ]; then
    EXTRA_ARGS=$(cat /tmp/openwb_install_args)
    ARGS="$ARGS $EXTRA_ARGS"
fi

# Lade das ursprüngliche Script erneut
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_complete.sh | bash -s -- $ARGS
EOF
    
    # Nächsten Schritt speichern
    echo "$next_step" > /tmp/openwb_install_step
    chmod +x /tmp/openwb_install_continue.sh
    
    # Fortsetzung in systemd-Unit einrichten
    cat > /tmp/openwb-install-continue.service << 'EOF'
[Unit]
Description=OpenWB Installation Fortsetzung
After=network.target

[Service]
Type=oneshot
ExecStart=/tmp/openwb_install_continue.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    sudo mv /tmp/openwb-install-continue.service /etc/systemd/system/
    sudo chmod 644 /etc/systemd/system/openwb-install-continue.service
    sudo systemctl daemon-reload
    sudo systemctl enable openwb-install-continue.service
    
    log_warning "System wird in 5 Sekunden neu gestartet..."
    sleep 5
    sudo reboot
}

# Hilfsfunktion für Cleanup
cleanup() {
    log "Cleanup nach Installation..."
    sudo systemctl disable openwb-install-continue.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/openwb-install-continue.service
    sudo systemctl daemon-reload
    rm -f /tmp/openwb_install_step
    rm -f /tmp/openwb_install_args
    rm -f /tmp/openwb_install_continue.sh
    rm -f /tmp/openwb-install-continue.service
}

# Hauptfunktion
main() {
    local continue_step="$CONTINUE_STEP"

    if [ -n "$continue_step" ]; then
        log "Fortsetzung der Installation ab Schritt: $continue_step"
    fi
    
    echo "====================================================================="
    echo "   OpenWB Trixie - Komplette Installation"
    echo "====================================================================="
    echo ""
    echo "Dieses Script führt folgende Schritte automatisch durch:"
    echo "1. Repository klonen"
    echo "2. Update auf Debian Trixie"
    echo "3. Python 3.9.23 Installation"
    echo "4. OpenWB Installation"
    echo "5. Automatische Neustarts"
    echo ""
    echo "WARNUNG: Dieser Vorgang überschreibt die Standard-Python-Installation!"
    echo "Erstelle vorher ein Backup deines Systems!"
    echo ""
    
    if [ -z "$continue_step" ]; then
        read -p "Möchtest du fortfahren? (j/N): " -n 1 -r
        echo
        if [[ ! "$REPLY" =~ ^[Jj]$ ]]; then
            echo "Installation abgebrochen."
            exit 1
        fi
    fi
    
    # Schritt 1: Repository klonen (falls nicht bereits erledigt)
    if [ -z "$continue_step" ] || [ "$continue_step" = "1" ]; then
        log "=== Schritt 1: Repository klonen ==="
        
        # Prüfe ob bereits vorhanden
        if [ ! -d "/home/openwb/openwb-trixie" ]; then
            log "Git installieren..."
            sudo apt update
            sudo apt install git -y
            
            log "Repository klonen..."
            sudo mkdir -p /home/openwb
            cd /home/openwb
            git clone https://github.com/Xerolux/openwb-trixie.git
            cd openwb-trixie
        else
            log "Repository bereits vorhanden, überspringe..."
            cd /home/openwb/openwb-trixie
        fi
        
        log_success "Repository erfolgreich geklont"
    fi
    
    # Schritt 2: Update auf Debian Trixie
    if [ -z "$continue_step" ] || [ "$continue_step" = "2" ]; then
        log "=== Schritt 2: Update auf Debian Trixie ==="
        
        cd /home/openwb/openwb-trixie
        
        # Prüfe ob bereits Trixie installiert ist
        if is_trixie; then
            log "Trixie bereits installiert, überspringe..."
        else
            log "Trixie-Update wird durchgeführt..."
            chmod +x update_to_trixie.sh
            
            # Führe Update automatisch aus (mit 'j' Antwort)
            echo "j" | ./update_to_trixie.sh
            
            log_warning "Trixie-Update abgeschlossen, Neustart erforderlich"
            reboot_and_continue "3"
        fi
    fi
    
    # Schritt 3: Python Installation
    if [ -z "$continue_step" ] || [ "$continue_step" = "3" ]; then
        cd /home/openwb/openwb-trixie

        if [ "$USE_VENV" = true ]; then
            log "=== Schritt 3: Virtual Environment Setup (nutzt System-Python) ==="
            log "✓ Keine Python-Kompilierung nötig (spart 30-60 Min!)"

            log "Erstelle/aktualisiere Virtual Environment mit System-Python..."
            chmod +x install_python3.9.sh
            if OPENWB_VENV_NONINTERACTIVE=1 ./install_python3.9.sh --venv-only; then
                log_success "venv erfolgreich erstellt/aktualisiert"
            else
                log_error "Fehler beim venv-Setup"
                exit 1
            fi

            # Kein Neustart nötig bei venv-only Installation
            log_success "Python-Setup abgeschlossen (kein Neustart nötig)"
        else
            log "=== Schritt 3: Python 3.9.23 Kompilierung ==="
            log_warning "Dies dauert 30-60 Minuten!"

            # Prüfe ob Python 3.9.23 bereits installiert ist
            if python3 --version 2>/dev/null | grep -q "Python 3.9.23"; then
                log "Python 3.9.23 bereits installiert, überspringe..."
            else
                log "Python 3.9.23 wird kompiliert und installiert..."
                chmod +x install_python3.9.sh

                # OPENWB_VENV_NONINTERACTIVE=1 überspringt alle read-Prompts im Script
                OPENWB_VENV_NONINTERACTIVE=1 ./install_python3.9.sh

                log_warning "Python-Installation abgeschlossen, Neustart erforderlich"
                reboot_and_continue "4"
            fi
        fi
    fi
    
    # Schritt 4: OpenWB Installation
    if [ -z "$continue_step" ] || [ "$continue_step" = "4" ]; then
        log "=== Schritt 4: OpenWB Installation ==="
        
        # Prüfe ob OpenWB bereits installiert ist
        if [ -f "/var/www/html/openWB/openwb.sh" ] || [ -f "/home/openwb/openwb/openwb.sh" ]; then
            log "OpenWB bereits installiert, überspringe..."
        else
            log "OpenWB wird installiert..."
            curl -s https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh | sudo bash
            
            log_success "OpenWB erfolgreich installiert"
            reboot_and_continue "5"
        fi

        if [ "$USE_VENV" = true ]; then
            OPENWB_RUNTIME_DIR=""
            for candidate in "/var/www/html/openWB" "/home/openwb/openWB" "/home/openwb/openwb" "/opt/openWB"; do
                if [ -d "$candidate" ]; then
                    OPENWB_RUNTIME_DIR="$candidate"
                    break
                fi
            done
            if [ -n "$OPENWB_RUNTIME_DIR" ]; then
                configure_openwb_venv_runtime "$OPENWB_RUNTIME_DIR"
            fi
        fi
    fi
    
    # Schritt 5: Finale Überprüfung und Cleanup
    if [ -z "$continue_step" ] || [ "$continue_step" = "5" ]; then
        log "=== Schritt 5: Finale Überprüfung ==="
        
        # Warte kurz nach dem Neustart
        sleep 10
        
        log "Überprüfe Systemstatus..."
        
        # Python-Version prüfen
        if [ "$USE_VENV" = true ]; then
            if python3 --version &>/dev/null; then
                log_success "Python $(python3 --version 2>&1) installiert (System-Python)"
            else
                log_error "Python nicht gefunden"
            fi
        else
            if python3 --version 2>/dev/null | grep -q "Python 3.9.23"; then
                log_success "Python 3.9.23 erfolgreich installiert"
            else
                log_error "Python 3.9.23 nicht korrekt installiert"
            fi
        fi
        
        # Trixie-Version prüfen
        if is_trixie; then
            log_success "Debian Trixie erfolgreich installiert"
        else
            log_error "Debian Trixie nicht korrekt installiert"
        fi
        
        # OpenWB-Installation prüfen
        if [ -f "/var/www/html/openWB/openwb.sh" ] || [ -f "/home/openwb/openwb/openwb.sh" ]; then
            log_success "OpenWB erfolgreich installiert"
        else
            log_error "OpenWB nicht gefunden"
        fi
        
        # Cleanup
        cleanup
        
        log_success "=== Installation abgeschlossen! ==="
        echo ""
        echo "Zusammenfassung:"
        if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            echo "- Debian Trixie: ${VERSION_CODENAME:-${VERSION_ID:-unbekannt}}"
        else
            echo "- Debian Trixie: $(lsb_release -c 2>/dev/null || echo "Prüfe manuell mit 'lsb_release -a'")"
        fi
        echo "- Python Version: $(python3 --version 2>/dev/null || echo "Fehler beim Abrufen")"

        if [ "$USE_VENV" = true ] && [ -d "/opt/openwb-venv" ]; then
            echo "- Virtual Environment: /opt/openwb-venv (✓ installiert)"
            echo "  Aktivieren: openwb-activate"
        fi

        echo "- OpenWB Status: $(systemctl is-active openwb 2>/dev/null || echo "Prüfe manuell mit 'systemctl status openwb'")"
        echo ""
        echo "Nächste Schritte:"
        echo "1. Öffne einen Browser und gehe zu: http://$(hostname -I | awk '{print $1}')"
        echo "2. Konfiguriere OpenWB über das Web-Interface"

        if [ "$USE_VENV" = true ]; then
            echo "3. Bei Python-Skripten: Nutze 'openwb-activate python script.py'"
        fi

        echo ""
        log_success "Installation erfolgreich beendet!"
    fi
}

# Script ausführen
main
