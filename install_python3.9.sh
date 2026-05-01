#!/bin/bash

# Python Installation und Virtual Environment Setup für OpenWB
#
# NEUE LOGIK (optimiert für Trixie):
# - Ohne Flags: Kompiliert Python 3.9.25 (Legacy-Kompatibilität, langsam!)
# - Mit --with-venv oder --venv-only: Nutzt System-Python (schnell!)
#
# Optionen:
#   --with-venv    Erstellt venv mit System-Python (KEINE Kompilierung, empfohlen!)
#   --venv-only    Nur venv erstellen/aktualisieren (KEINE Python-Installation)
#   --help         Zeigt diese Hilfe
#
# Umgebungsvariablen:
#   OPENWB_VENV_NONINTERACTIVE=1   Keine interaktiven Rückfragen (für automatische Aufrufe)

set -Ee -o pipefail

on_error() {
    local exit_code="$1"
    local line_no="$2"
    local cmd="$3"
    echo "✗ Fehler in Zeile $line_no: $cmd (Exit-Code: $exit_code)"
    echo "  Häufige Ursachen: fehlende apt-Pakete, Netzwerkproblem oder PEP668 bei System-pip."
    echo "  Tipp: Für stabile Installation nutze '--venv-only' oder '--with-venv'."
}

trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

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
            echo "OpenWB Python Installation für Debian Trixie"
            echo ""
            echo "Verwendung: $0 [OPTIONEN]"
            echo ""
            echo "Optionen:"
            echo "  (keine)         Legacy-Modus: Kompiliert Python 3.9.25 (langsam!)"
            echo "                  Überschreibt System-Python"
            echo ""
            echo "  --with-venv     Modern: Nutzt System-Python + venv (EMPFOHLEN!)"
            echo "                  ✓ Keine Kompilierung (spart 30-60 Min)"
            echo "                  ✓ Nutzt Trixie System-Python (3.12+)"
            echo "                  ✓ Kompatibel mit Python 3.13/3.14/3.15 im venv-Modus"
            echo "                  ✓ Überlebt OpenWB-Updates"
            echo ""
            echo "  --venv-only     Nur venv erstellen/aktualisieren"
            echo "                  (für Updates oder frische Trixie-Installation)"
            echo ""
            echo "  --help          Zeigt diese Hilfe"
            echo ""
            echo "Umgebungsvariablen:"
            echo "  OPENWB_VENV_NONINTERACTIVE=1   Keine Rückfragen (für Skript-Aufrufe)"
            echo ""
            echo "Empfohlen: ./install_python3.9.sh --with-venv"
            echo ""
            exit 0
            ;;
        *)
            echo "Unbekannte Option: $1"
            echo "Verwende --help für Hilfe"
            exit 1
            ;;
    esac
done

# Hilfsfunktion: PHP-Version dynamisch ermitteln
detect_php_version() {
    local v
    if command -v php >/dev/null 2>&1; then
        v=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null)
        [ -n "$v" ] && echo "$v" && return
    fi
    for v in 8.4 8.3 8.2 8.1; do
        [ -d "/etc/php/$v" ] && echo "$v" && return
    done
    echo "8.4"
}

# Hilfsfunktion: OpenWB-Runtime auf venv-Python/pip umstellen (PEP668-Fix)
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
        echo "⚠ venv-Python/Pip nicht gefunden, überspringe Runtime-Anpassungen"
        return 0
    fi

    echo "Stelle OpenWB Runtime auf venv um: $openwb_dir"

    # Services stoppen vor dem Patchen (verhindert Race Conditions)
    for svc in openwb2 openwb; do
        if systemctl is-active "$svc" &>/dev/null; then
            sudo systemctl stop "$svc" \
                && echo "  Gestoppt: $svc" \
                || echo "  ⚠ Konnte $svc nicht stoppen (wird ignoriert)"
        fi
    done

    if [ -f "$service_file" ]; then
        sudo sed -i "s#^ExecStart=.*#ExecStart=$venv_python $openwb_dir/packages/main.py#g" "$service_file"
        echo "  ✓ openwb2.service auf venv-Python umgestellt"
    else
        echo "  ⚠ openwb2.service nicht gefunden: $service_file"
    fi

    if [ -f "$atreboot_file" ]; then
        sudo sed -i "s#\\([^[:alnum:]_/.-]\\|^\\)pip3 install -r#\\1$venv_pip install -r#g" "$atreboot_file"
        sudo sed -i -E 's@(^|[^[:alnum:]_/.-])pip3[[:space:]]+install[[:space:]]+--only-binary@\1/opt/openwb-venv/bin/pip3 install --only-binary@g' "$atreboot_file"
        sudo sed -i 's|pip uninstall urllib3 -y|/opt/openwb-venv/bin/pip3 uninstall urllib3 -y|g' "$atreboot_file"
        echo "  ✓ atreboot.sh auf venv-pip umgestellt (PEP668-sicher)"
    else
        echo "  ⚠ atreboot.sh nicht gefunden: $atreboot_file"
    fi

    if [ -f "$remote_service_file" ]; then
        sudo sed -i "s#^ExecStart=.*#ExecStart=$venv_python $openwb_dir/runs/remoteSupport/remoteSupport.py#g" "$remote_service_file"
        echo "  ✓ openwbRemoteSupport.service auf venv-Python umgestellt"
    fi

    sudo systemctl daemon-reload || true

    # Services neu starten nach dem Patchen
    for svc in openwb2 openwb; do
        if systemctl is-enabled "$svc" &>/dev/null; then
            sudo systemctl restart "$svc" \
                && echo "  ✓ Neugestartet: $svc" \
                || echo "  ⚠ Konnte $svc nicht neustarten"
        fi
    done

    echo "✓ openWB Runtime auf venv umgestellt"
}

echo "====================================================================="
echo "   OpenWB Python Installation"
echo "====================================================================="
if [ "$VENV_ONLY" = true ]; then
    echo "Modus: Virtual Environment Setup (nutzt System-Python)"
    echo "✓ Keine Python-Kompilierung"
    echo "✓ Schnelle Installation"
elif [ "$INSTALL_VENV" = true ]; then
    echo "Modus: venv-Installation mit System-Python"
    echo "✓ Keine Python-Kompilierung (spart 30-60 Min!)"
    echo "✓ Nutzt Debian Trixie System-Python"
    echo "✓ Isolierte Paket-Installation"
else
    echo "Modus: Legacy - Python 3.9.25 Kompilierung"
    echo "⚠ WARNUNG: Überschreibt System-Python!"
    echo "⚠ Dauert 30-60 Minuten!"
    echo ""
    if [[ "${OPENWB_VENV_NONINTERACTIVE:-0}" != "1" ]]; then
        read -p "Möchtest du stattdessen --with-venv nutzen? (empfohlen) (j/N): " -n 1 -r < /dev/tty
        echo
        if [[ "$REPLY" =~ ^[Jj]$ ]]; then
            echo "Starte mit --with-venv..."
            INSTALL_VENV=true
            VENV_ONLY=true
        fi
    fi
fi
echo ""

# Überspringe Python-Kompilierung wenn venv verwendet wird
if [ "$INSTALL_VENV" = false ]; then

# 0. OpenWB Konfiguration zu config.txt hinzufügen
echo "0. OpenWB Konfiguration wird hinzugefügt..."

# Ermittle korrekten config.txt Pfad
if [ -f "/boot/firmware/config.txt" ]; then
    CONFIG_TXT="/boot/firmware/config.txt"
elif [ -f "/boot/config.txt" ]; then
    CONFIG_TXT="/boot/config.txt"
else
    echo "WARNUNG: config.txt nicht gefunden - GPIO-Konfiguration übersprungen"
    CONFIG_TXT=""
fi

if [ -n "$CONFIG_TXT" ]; then
    sudo cp "$CONFIG_TXT" "${CONFIG_TXT}.backup.$(date +%Y%m%d_%H%M%S)"

    # Audio deaktivieren (dtparam=audio=on zu dtparam=audio=off)
    echo "Audio wird deaktiviert..."
    sudo sed -i 's/dtparam=audio=on/dtparam=audio=off/g' "$CONFIG_TXT"

    # vc4-kms-v3d auskommentieren
    echo "vc4-kms-v3d wird auskommentiert..."
    sudo sed -i 's/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/g' "$CONFIG_TXT"

    # OpenWB Konfiguration hinzufügen (nur wenn noch nicht vorhanden)
    if ! grep -q "# openwb - begin" "$CONFIG_TXT"; then
        sudo tee -a "$CONFIG_TXT" > /dev/null << 'EOF'
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
        echo "OpenWB Konfiguration hinzugefügt. Backup erstellt als ${CONFIG_TXT}.backup.*"
    else
        echo "OpenWB Konfiguration bereits vorhanden, überspringe..."
    fi
    echo "Audio deaktiviert (dtparam=audio=off) und vc4-kms-v3d auskommentiert"
fi

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
    liblgpio-dev \
    libgpiod-dev \
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

# 3. Python 3.9.25 Quellcode herunterladen
echo "3. Python 3.9.25 Quellcode wird heruntergeladen..."
cd /tmp
wget https://www.python.org/ftp/python/3.9.25/Python-3.9.25.tar.xz

# 4. Archiv extrahieren
echo "4. Archiv wird extrahiert..."
tar -xJf Python-3.9.25.tar.xz
cd Python-3.9.25

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
available_ram=$(free -g | awk 'NR==2{print $7}')
available_ram=${available_ram:-0}
cpu_cores=$(nproc)

if [ "$available_ram" -lt 2 ]; then
    echo "Wenig RAM erkannt ($available_ram GB), verwende 1 Job..."
    make -j1
elif [ "$available_ram" -lt 4 ]; then
    echo "Mittlerer RAM erkannt ($available_ram GB), verwende 2 Jobs..."
    make -j2
else
    jobs=$((cpu_cores > 4 ? 4 : cpu_cores))
    echo "Genug RAM erkannt ($available_ram GB), verwende $jobs Jobs..."
    make -j$jobs
fi

# 7. Tests ausführen (optional - Testfehler sollen Installation nicht abbrechen)
echo "7. Tests werden ausgeführt..."
make test || echo "WARNUNG: Einige Tests fehlgeschlagen (kann ignoriert werden)"

# 8. Installation (WARNUNG: Überschreibt Standard-Python!)
echo "8. Installation wird durchgeführt..."
echo "WARNUNG: Dies überschreibt die Standard-Python-Installation!"

if [[ "${OPENWB_VENV_NONINTERACTIVE:-0}" = "1" ]]; then
    confirm="y"
else
    read -p "Möchten Sie fortfahren? (y/N): " confirm
fi

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

    # 12. rpi-lgpio Paket installieren (nutzt frisch gebautes Python 3.9, kein PEP668-Problem)
    echo "12. rpi-lgpio Paket wird installiert..."
    /usr/local/bin/pip3 install rpi-lgpio

    echo "=== Installation abgeschlossen ==="
    echo "Python 3.9.25 ist jetzt als Standard-Python installiert"
    echo "Verfügbare Befehle: python, python3, pip, pip3"
    echo "rpi-lgpio wurde installiert"

    # 13. PHP Upload-Limits konfigurieren (PHP-Version dynamisch ermitteln)
    echo "13. PHP Upload-Limits werden konfiguriert..."
    PHP_VER=$(detect_php_version)
    echo "Erkannte PHP-Version: $PHP_VER"
    sudo mkdir -p "/etc/php/$PHP_VER/apache2/conf.d/"
    printf 'upload_max_filesize = 300M\npost_max_size = 300M\n' | sudo tee "/etc/php/$PHP_VER/apache2/conf.d/20-uploadlimit.ini" > /dev/null

    echo "PHP Upload-Limits auf 300M gesetzt:"
    cat "/etc/php/$PHP_VER/apache2/conf.d/20-uploadlimit.ini"

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
rm -rf /tmp/Python-3.9.25*

fi  # Ende von if [ "$INSTALL_VENV" = false ]

# Virtual Environment Setup (wenn --with-venv oder --venv-only)
if [ "$INSTALL_VENV" = true ]; then
    echo ""
    echo "====================================================================="
    echo "   Virtual Environment Setup"
    echo "====================================================================="

    echo "Installiere benötigte venv-Systempakete..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-venv python3-pip

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VENV_SETUP="$SCRIPT_DIR/setup_venv.sh"
    POST_UPDATE_HOOK="$SCRIPT_DIR/openwb_post_update_hook.sh"

    if [ ! -f "$VENV_SETUP" ]; then
        echo "FEHLER: setup_venv.sh nicht gefunden: $VENV_SETUP"
        echo "venv-Setup wird übersprungen"
        exit 1
    fi

    echo "Führe venv-Setup aus..."
    chmod +x "$VENV_SETUP"
    if OPENWB_VENV_NONINTERACTIVE=1 bash "$VENV_SETUP"; then
        echo "✓ Virtual Environment erfolgreich eingerichtet"
        echo ""

        # OpenWB Runtime auf venv umstellen (PEP668-Fix für atreboot.sh und Services)
        echo "=== OpenWB Runtime auf venv umstellen ==="
        OPENWB_RUNTIME_PATCHED=false
        for openwb_dir in "/var/www/html/openWB" "/home/openwb/openWB" "/home/openwb/openwb" "/opt/openWB"; do
            if [ -d "$openwb_dir" ]; then
                configure_openwb_venv_runtime "$openwb_dir"
                OPENWB_RUNTIME_PATCHED=true
                break
            fi
        done
        if [ "$OPENWB_RUNTIME_PATCHED" = false ]; then
            echo "⚠ OpenWB noch nicht installiert - Runtime-Patch wird nach OpenWB-Installation nötig"
            echo "  Führe nach der OpenWB-Installation aus:"
            echo "  OPENWB_VENV_NONINTERACTIVE=1 ./install_python3.9.sh --venv-only"
        fi

        # asyncio.coroutine Kompatibilitäts-Shim für Python 3.11+
        PY_VER=$(/opt/openwb-venv/bin/python3 -c 'import sys; v=sys.version_info; print(f"{v.major}.{v.minor}")' 2>/dev/null || echo "0.0")
        PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
        PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
        if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 11 ]; then
            SHIM_DIR="/opt/openwb-venv/lib/python${PY_MAJOR}.${PY_MINOR}/site-packages"
            if [ ! -f "$SHIM_DIR/openwb_py313_compat.py" ]; then
                echo "Installiere asyncio.coroutine Shim für Python ${PY_MAJOR}.${PY_MINOR}..."
                sudo mkdir -p "$SHIM_DIR"
                sudo tee "$SHIM_DIR/openwb_py313_compat.py" > /dev/null << 'PYEOF'
import asyncio
import types
import sys
if sys.version_info >= (3, 11) and not hasattr(asyncio, "coroutine"):
    def _coroutine_compat(func):
        return types.coroutine(func)
    asyncio.coroutine = _coroutine_compat
PYEOF
                echo "import openwb_py313_compat" | sudo tee "$SHIM_DIR/openwb_py313_compat.pth" > /dev/null
                sudo chown openwb:openwb "$SHIM_DIR/openwb_py313_compat.py" "$SHIM_DIR/openwb_py313_compat.pth" 2>/dev/null || true
                echo "✓ asyncio.coroutine Shim installiert"
            fi
        fi

        echo ""

        # Post-Update Hook Installation
        echo "=== Post-Update Hook Installation ==="
        if [ -f "$POST_UPDATE_HOOK" ]; then
            HOOK_INSTALLED=false
            for openwb_dir in "/var/www/html/openWB" "/home/openwb/openWB" "/opt/openWB"; do
                if [ -d "$openwb_dir" ]; then
                    echo "OpenWB gefunden in: $openwb_dir"
                    sudo mkdir -p "$openwb_dir/data/config" 2>/dev/null || true
                    if sudo cp "$POST_UPDATE_HOOK" "$openwb_dir/data/config/post-update.sh" 2>/dev/null; then
                        sudo chmod +x "$openwb_dir/data/config/post-update.sh"
                        echo "✓ Post-Update Hook installiert: $openwb_dir/data/config/post-update.sh"
                        HOOK_INSTALLED=true
                        break
                    fi
                fi
            done

            if [ "$HOOK_INSTALLED" = false ]; then
                echo "⚠ OpenWB noch nicht installiert"
                echo "  Hook wird später automatisch installiert"
                echo "  Oder manuell nach OpenWB-Installation:"
                echo "  sudo cp $POST_UPDATE_HOOK /var/www/html/openWB/data/config/post-update.sh"
                echo "  sudo chmod +x /var/www/html/openWB/data/config/post-update.sh"
            fi
        else
            echo "⚠ Post-Update Hook nicht gefunden: $POST_UPDATE_HOOK"
        fi

        echo ""
        echo "====================================================================="
        echo "   Installation abgeschlossen!"
        echo "====================================================================="
        echo ""
        echo "Python-Version im venv:"
        source /opt/openwb-venv/bin/activate
        python --version
        deactivate
        echo ""
        echo "Verwendung:"
        echo "  1. Aktivieren: source /opt/openwb-venv/bin/activate"
        echo "  2. Wrapper: openwb-activate python script.py"
        echo "  3. Update: $0 --venv-only"
        echo ""
        echo "Vorteile:"
        echo "  ✓ Keine Python-Kompilierung (30-60 Min gespart!)"
        echo "  ✓ Nutzt modernes System-Python"
        echo "  ✓ Überlebt OpenWB-Updates automatisch"
        echo "  ✓ Post-Update Hook installiert (automatische Updates)"
        echo ""
    else
        echo "✗ Fehler beim venv-Setup"
        echo "  Prüfe die Ausgabe oberhalb (klarer Fehlerhinweis durch setup_venv.sh)."
        echo "  Kurztest: OPENWB_VENV_NONINTERACTIVE=1 ./setup_venv.sh --update"
        exit 1
    fi
fi

echo ""
echo "=== Script beendet ==="

if [ "$INSTALL_VENV" = true ]; then
    echo ""
    echo "Nächste Schritte:"
    echo "  1. Installiere OpenWB (falls noch nicht geschehen)"
    echo "  2. Nutze 'openwb-activate' für Python-Skripte"
    echo "  3. Das venv wird automatisch nach OpenWB-Updates aktualisiert"
fi
