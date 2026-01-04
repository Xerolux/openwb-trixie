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

set -e  # Script bei Fehlern beenden

# Parse Argumente
USE_VENV=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --with-venv)
            USE_VENV=true
            shift
            ;;
        --continue)
            # Wird intern für Fortsetzung verwendet
            shift
            break
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
            # Unbekannte Argumente weitergeben
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

# Hilfsfunktion für Neustarts
reboot_and_continue() {
    local next_step=$1
    log_warning "Erstelle Fortsetzungsscript für nächsten Schritt: $next_step"
    
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

# Lade das ursprüngliche Script erneut
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_complete.sh | bash -s -- --continue $STEP
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
    rm -f /tmp/openwb_install_continue.sh
    rm -f /tmp/openwb-install-continue.service
}

# Hauptfunktion
main() {
    local continue_step=""
    
    # Überprüfe ob wir ein continue-Flag haben
    if [ "$1" = "--continue" ]; then
        continue_step="$2"
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
        if [[ ! $REPLY =~ ^[Jj]$ ]]; then
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
        if grep -q "trixie" /etc/debian_version 2>/dev/null || lsb_release -c 2>/dev/null | grep -q "trixie"; then
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

            # Prüfe ob venv bereits existiert
            if [ -d "/opt/openwb-venv" ]; then
                log "venv bereits vorhanden, aktualisiere..."
                chmod +x install_python3.9.sh
                ./install_python3.9.sh --venv-only
            else
                log "Erstelle Virtual Environment mit System-Python..."
                chmod +x install_python3.9.sh
                ./install_python3.9.sh --venv-only

                if [ $? -eq 0 ]; then
                    log_success "venv erfolgreich erstellt"
                else
                    log_error "Fehler beim venv-Setup"
                    exit 1
                fi
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

                # Führe Installation automatisch aus (mit 'y' Antwort)
                echo "y" | ./install_python3.9.sh

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
    fi
    
    # Schritt 5: Finale Überprüfung und Cleanup
    if [ -z "$continue_step" ] || [ "$continue_step" = "5" ]; then
        log "=== Schritt 5: Finale Überprüfung ==="
        
        # Warte kurz nach dem Neustart
        sleep 10
        
        log "Überprüfe Systemstatus..."
        
        # Python-Version prüfen
        if python3 --version 2>/dev/null | grep -q "Python 3.9.23"; then
            log_success "Python 3.9.23 erfolgreich installiert"
        else
            log_error "Python 3.9.23 nicht korrekt installiert"
        fi
        
        # Trixie-Version prüfen
        if lsb_release -c 2>/dev/null | grep -q "trixie" || grep -q "trixie" /etc/debian_version 2>/dev/null; then
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
        echo "- Debian Trixie: $(lsb_release -c 2>/dev/null || echo "Prüfe manuell mit 'lsb_release -a'")"
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

# Fehlerbehandlung
trap 'log_error "Fehler in Zeile $LINENO. Prüfe die Logs und führe die Installation manuell fort."' ERR

# Script ausführen
main "$@"
