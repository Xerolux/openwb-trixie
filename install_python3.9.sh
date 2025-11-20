#!/bin/bash

# Python 3.9.23 kompilieren und installieren
# WARNUNG: make install überschreibt die Standard-Python-Installation!
#
# Optionen:
#   --with-venv    Erstellt zusätzlich ein isoliertes venv für OpenWB
#   --venv-only    Überspringt Python-Installation, erstellt nur venv
#   --help         Zeigt diese Hilfe

# Parse Argumente
INSTALL_VENV=false
VENV_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --with-venv)
            INSTALL_VENV=true
            shift
            ;;
        --venv-only)
            VENV_ONLY=true
            INSTALL_VENV=true
            shift
            ;;
        --help|-h)
            echo "Verwendung: $0 [OPTIONEN]"
            echo ""
            echo "Optionen:"
            echo "  (keine)         Standardinstallation (überschreibt System-Python)"
            echo "  --with-venv     Installiert Python + erstellt isoliertes venv"
            echo "  --venv-only     Überspringt Python-Installation, erstellt nur venv"
            echo "  --help          Zeigt diese Hilfe"
            echo ""
            echo "Empfohlen: --with-venv für produktive Umgebungen"
            exit 0
            ;;
        *)
            echo "Unbekannte Option: $1"
            echo "Verwende --help für Hilfe"
            exit 1
            ;;
    esac
done

echo "=== Python 3.9.23 Installation ==="
if [ "$VENV_ONLY" = true ]; then
    echo "Modus: Nur venv-Erstellung"
elif [ "$INSTALL_VENV" = true ]; then
    echo "Modus: Python-Installation + venv"
else
    echo "Modus: Standard (Python-Installation ohne venv)"
fi
echo ""

# Überspringe Python-Installation wenn --venv-only
if [ "$VENV_ONLY" = false ]; then

# 0. OpenWB Konfiguration zu /boot/firmware/config.txt hinzufügen
echo "0. OpenWB Konfiguration wird zu /boot/firmware/config.txt hinzugefügt..."
sudo cp /boot/firmware/config.txt /boot/firmware/config.txt.backup

# Audio deaktivieren (dtparam=audio=on zu dtparam=audio=off)
echo "Audio wird deaktiviert..."
sudo sed -i 's/dtparam=audio=on/dtparam=audio=off/g' /boot/firmware/config.txt

# vc4-kms-v3d auskommentieren
echo "vc4-kms-v3d wird auskommentiert..."
sudo sed -i 's/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/g' /boot/firmware/config.txt

# OpenWB Konfiguration hinzufügen
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

echo "OpenWB Konfiguration hinzugefügt. Backup erstellt als /boot/firmware/config.txt.backup"
echo "Audio deaktiviert (dtparam=audio=off) und vc4-kms-v3d auskommentiert"

# 1. System aktualisieren
echo "1. System wird aktualisiert..."
sudo apt update && sudo apt upgrade -y

# 2. System-Pakete und Abhängigkeiten installieren
echo "2. System-Pakete und Build-Abhängigkeiten werden installiert..."
sudo apt-get -q -y install \
    vim bc jq socat sshpass sudo ssl-cert mmc-utils \
    apache2 libapache2-mod-php \
    php php-gd php-curl php-xml php-json \
    git \
    mosquitto mosquitto-clients \
    python3-pip \
    xserver-xorg x11-xserver-utils openbox-lxde-session lightdm lightdm-autologin-greeter accountsservice \
    chromium chromium-l10n \
    build-essential \
    zlib1g-dev \
    libncurses5-dev \
    libgdbm-dev \
    libnss3-dev \
    libssl-dev \
    libsqlite3-dev \
    libreadline-dev \
    libffi-dev \
    libbz2-dev \
    liblzma-dev \
    libgdbm-compat-dev \
    libdb5.3-dev \
    uuid-dev \
    tk-dev \
    libexpat1-dev \
    libmpdec-dev \
    wget \
    curl \
    make \
    gcc \
    g++ \
    pkg-config

# 3. Python 3.9.23 Quellcode herunterladen
echo "3. Python 3.9.23 Quellcode wird heruntergeladen..."
cd /tmp
wget https://www.python.org/ftp/python/3.9.23/Python-3.9.23.tgz

# 4. Archiv extrahieren
echo "4. Archiv wird extrahiert..."
tar -xzf Python-3.9.23.tgz
cd Python-3.9.23

# 5. Konfiguration (ohne LTO für weniger RAM-Verbrauch)
echo "5. Python wird konfiguriert..."
./configure \
    --enable-optimizations \
    --with-ensurepip=install \
    --enable-shared \
    --enable-loadable-sqlite-extensions \
    --with-system-expat \
    --with-system-ffi

# 6. Kompilierung (begrenzte Parallelität für weniger RAM-Verbrauch)
echo "6. Kompilierung startet... (Das kann einige Zeit dauern)"
# Prüfe verfügbaren RAM und CPU-Kerne
available_ram=$(free -g | awk 'NR==2{print $7}')
cpu_cores=$(nproc)

if [ "$available_ram" -lt 2 ]; then
    # Wenig RAM: Nur 1 Job parallel
    echo "Wenig RAM erkannt ($available_ram GB), verwende 1 Job..."
    make -j1
elif [ "$available_ram" -lt 4 ]; then
    # Mittlerer RAM: 2 Jobs parallel
    echo "Mittlerer RAM erkannt ($available_ram GB), verwende 2 Jobs..."
    make -j2
else
    # Genug RAM: Maximal 4 Jobs (auch bei mehr CPU-Kernen)
    jobs=$((cpu_cores > 4 ? 4 : cpu_cores))
    echo "Genug RAM erkannt ($available_ram GB), verwende $jobs Jobs..."
    make -j$jobs
fi

# 7. Tests ausführen (optional, aber empfohlen)
echo "7. Tests werden ausgeführt..."
make test

# 8. Installation (WARNUNG: Überschreibt Standard-Python!)
echo "8. Installation wird durchgeführt..."
echo "WARNUNG: Dies überschreibt die Standard-Python-Installation!"
read -p "Möchten Sie fortfahren? (y/N): " confirm
if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    sudo make install
    
    # 9. ldconfig ausführen für shared libraries
    echo "9. Shared libraries werden aktualisiert..."
    sudo ldconfig
    
    # 10. Symbolische Links erstellen
    echo "10. Symbolische Links werden erstellt..."
    sudo ln -sf /usr/local/bin/python3 /usr/local/bin/python
    sudo ln -sf /usr/local/bin/pip3 /usr/local/bin/pip
    
    echo "Erstellte Links:"
    ls -la /usr/local/bin/python*
    ls -la /usr/local/bin/pip*
    
    # 11. Neue Python-Version testen
    echo "11. Installation wird getestet..."
    python3 --version
    python --version
    pip3 --version
    pip --version
    python3 -c "import sys; print(sys.version)"
    
    # 12. rpi-lgpio Paket installieren
    echo "12. rpi-lgpio Paket wird installiert..."
    pip3 install rpi-lgpio
    
    echo "=== Installation abgeschlossen ==="
    echo "Python 3.9.23 ist jetzt als Standard-Python installiert"
    echo "Verfügbare Befehle: python, python3, pip, pip3"
    echo "rpi-lgpio wurde installiert"
    
    # 13. PHP Upload-Limits konfigurieren
    echo "13. PHP Upload-Limits werden konfiguriert..."
    sudo mkdir -p /etc/php/8.4/apache2/conf.d/
    echo "upload_max_filesize = 300M" | sudo tee /etc/php/8.4/apache2/conf.d/20-uploadlimit.ini > /dev/null
    echo "post_max_size = 300M" | sudo tee -a /etc/php/8.4/apache2/conf.d/20-uploadlimit.ini > /dev/null
    
    echo "PHP Upload-Limits auf 300M gesetzt:"
    cat /etc/php/8.4/apache2/conf.d/20-uploadlimit.ini
    
    # Apache neu starten für PHP-Änderungen
    echo "Apache wird neu gestartet..."
    sudo systemctl restart apache2
    
    echo "=== Vollständige Installation beendet ==="
    echo "HINWEIS: Ein Neustart ist erforderlich, damit die OpenWB GPIO-Konfiguration wirksam wird!"
else
    echo "Installation abgebrochen."
    echo "Tipp: Verwenden Sie 'make altinstall' für eine sichere Installation"
    exit 1
fi

# Aufräumen
echo "Temporäre Dateien werden bereinigt..."
cd /
rm -rf /tmp/Python-3.9.23*

fi  # Ende von if [ "$VENV_ONLY" = false ]

# Virtual Environment Setup (wenn --with-venv oder --venv-only)
if [ "$INSTALL_VENV" = true ]; then
    echo ""
    echo "=== Virtual Environment Setup ==="

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VENV_SETUP="$SCRIPT_DIR/setup_venv.sh"

    if [ ! -f "$VENV_SETUP" ]; then
        echo "FEHLER: setup_venv.sh nicht gefunden: $VENV_SETUP"
        echo "venv-Setup wird übersprungen"
    else
        echo "Führe venv-Setup aus..."
        chmod +x "$VENV_SETUP"
        bash "$VENV_SETUP"

        if [ $? -eq 0 ]; then
            echo "✓ Virtual Environment erfolgreich eingerichtet"
            echo ""
            echo "Verwendung:"
            echo "  1. Aktivieren: source /opt/openwb-venv/bin/activate"
            echo "  2. Wrapper: openwb-activate python script.py"
            echo "  3. Update: $0 --venv-only"
        else
            echo "✗ Fehler beim venv-Setup"
            exit 1
        fi
    fi
fi

echo ""
echo "=== Script beendet ==="

if [ "$INSTALL_VENV" = true ]; then
    echo ""
    echo "Empfehlung:"
    echo "- Verwende das venv für alle OpenWB-Python-Skripte"
    echo "- Das venv überlebt OpenWB-Updates"
    echo "- Aktualisiere das venv nach Updates mit: $0 --venv-only"
fi
