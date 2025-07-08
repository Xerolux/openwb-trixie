#!/bin/bash

# Python 3.9.23 kompilieren und installieren
# WARNUNG: make install überschreibt die Standard-Python-Installation!

echo "=== Python 3.9.23 Kompilierung startet ==="

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
    
    echo "=== Installation abgeschlossen ==="
    echo "Python 3.9.23 ist jetzt als Standard-Python installiert"
    echo "Verfügbare Befehle: python, python3, pip, pip3"
    
    # 12. PHP Upload-Limits konfigurieren
    echo "12. PHP Upload-Limits werden konfiguriert..."
    sudo mkdir -p /etc/php/8.4/apache2/conf.d/
    echo "upload_max_filesize = 300M" | sudo tee /etc/php/8.4/apache2/conf.d/20-uploadlimit.ini > /dev/null
    echo "post_max_size = 300M" | sudo tee -a /etc/php/8.4/apache2/conf.d/20-uploadlimit.ini > /dev/null
    
    echo "PHP Upload-Limits auf 300M gesetzt:"
    cat /etc/php/8.4/apache2/conf.d/20-uploadlimit.ini
    
    # Apache neu starten für PHP-Änderungen
    echo "Apache wird neu gestartet..."
    sudo systemctl restart apache2
    
    echo "=== Vollständige Installation beendet ==="
else
    echo "Installation abgebrochen."
    echo "Tipp: Verwenden Sie 'make altinstall' für eine sichere Installation"
fi

# Aufräumen
echo "Temporäre Dateien werden bereinigt..."
cd /
rm -rf /tmp/Python-3.9.23*

echo "=== Script beendet ==="
