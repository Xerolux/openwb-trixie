#!/bin/bash

# ============================================================================
# OpenWB Trixie Installer - Ein Script für alles
# ============================================================================
# Für FRISCHE Debian Trixie Installationen (kein Bookworm-Upgrade!)
#
# Verwendung:
#   bash <(curl -fsSL -H "Cache-Control: no-cache" \
#     https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh)
#
#   Oder mit Option:
#   ./install.sh --venv           System-Python + venv (empfohlen, schnell)
#   ./install.sh --python39       Python 3.9.25 kompilieren (Legacy, Original)
#   ./install.sh --python314      Python 3.14.4 kompilieren + venv (neuestes Python)
#   ./install.sh --patches        Feature-Patches verwalten
#   ./install.sh --help           Hilfe anzeigen
#
# Getestet auf: x86_64, ARM64, ARM32, Proxmox, Raspberry Pi
# ============================================================================

set -Ee -o pipefail

INSTALLER_VERSION="2026-05-01"
BUILD_ID="4186526"

# ============================================================================
# Argumente parsen
# ============================================================================
MODE="${MODE:-}"
NONINTERACTIVE="${NONINTERACTIVE:-0}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --venv|-v)
            MODE="venv"
            shift
            ;;
        --python39|--legacy|-l)
            MODE="python39"
            shift
            ;;
        --python314|--latest|-p)
            MODE="python314"
            shift
            ;;
        --patches)
            MODE="patches"
            shift
            ;;
        --non-interactive|-n)
            NONINTERACTIVE=1
            shift
            ;;
        --help|-h)
            head -20 "$0" | grep -v '^#!/' | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)
            echo "Unbekannte Option: $1"
            echo "Nutze --help für Hilfe"
            exit 1
            ;;
    esac
done

# ============================================================================
# Farben und Logging
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()       { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
log_success() { echo -e "${GREEN}[$(date +'%H:%M:%S')] OK${NC} $1"; }
log_warning() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN${NC} $1"; }
log_error()   { echo -e "${RED}[$(date +'%H:%M:%S')] FEHLER${NC} $1"; }
log_step()    { echo -e "\n${CYAN}━━━ $1 ━━━${NC}\n"; }

on_error() {
    local exit_code="$1"
    local line_no="$2"
    local cmd="$3"
    log_error "Zeile $line_no: $cmd (Exit: $exit_code)"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

# ============================================================================
# Konfiguration
# ============================================================================
OPENWB_USER="openwb"
VENV_DIR="/opt/openwb-venv"
OPENWB_DIR="/var/www/html/openWB"
PATCH_DIR="/opt/openwb-patches"
PATCH_CONF="$PATCH_DIR/enabled.conf"
if _src_dir="$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" && _tgt="$(cd "$_src_dir" 2>/dev/null && pwd)"; then
    SCRIPT_DIR="$_tgt"
else
    SCRIPT_DIR="$HOME"
fi
OPENWB_TRIXIE_URL="${OPENWB_TRIXIE_URL:-https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh}"

# ============================================================================
# Hilfsfunktionen: Plattform-Erkennung
# ============================================================================
is_arm_arch() {
    case "$(uname -m 2>/dev/null || true)" in
        arm*|aarch64) return 0 ;;
        *) return 1 ;;
    esac
}

is_raspberry_pi() {
    local model=""
    if [ -r /proc/device-tree/model ]; then
        model=$(tr -d '\000' < /proc/device-tree/model)
    elif [ -r /sys/firmware/devicetree/base/model ]; then
        model=$(tr -d '\000' < /sys/firmware/devicetree/base/model)
    fi
    printf '%s\n' "$model" | grep -qi "raspberry pi"
}

is_trixie() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        if [ "${VERSION_CODENAME:-}" = "trixie" ] || printf '%s\n' "${VERSION:-}" | grep -qi 'trixie'; then
            return 0
        fi
    fi
    command -v lsb_release >/dev/null 2>&1 && lsb_release -c 2>/dev/null | grep -q "trixie"
}

detect_php_version() {
    local v
    if command -v php >/dev/null 2>&1; then
        v=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null)
        [ -n "$v" ] && echo "$v" && return
    fi
    for v in 8.4 8.3 8.2; do
        [ -d "/etc/php/$v" ] && echo "$v" && return
    done
    echo "8.4"
}

get_venv_python_version() {
    if [ -x "$VENV_DIR/bin/python3" ]; then
        "$VENV_DIR/bin/python3" -c 'import sys; v=sys.version_info; print(f"{v.major}.{v_minor}")' 2>/dev/null
    fi
}

ensure_free_space_mb() {
    local min_mb="$1"
    local avail_mb
    avail_mb=$(df -Pm / | awk 'NR==2 {print $4}')
    if [ -n "$avail_mb" ] && [ "$avail_mb" -lt "$min_mb" ]; then
        log_error "Nur ${avail_mb} MB frei auf / (mindestens ${min_mb} MB benötigt)"
        exit 1
    fi
}

# ============================================================================
# Hilfsfunktionen: System-Konfiguration
# ============================================================================
ensure_openwb_user() {
    if id "$OPENWB_USER" >/dev/null 2>&1; then
        log "Benutzer '$OPENWB_USER' existiert"
    else
        log "Erstelle Benutzer '$OPENWB_USER'..."
        sudo useradd -m -s /bin/bash "$OPENWB_USER"
    fi
    if ! id -nG "$OPENWB_USER" | grep -qw sudo; then
        sudo usermod -aG sudo "$OPENWB_USER"
    fi
    if ! id -nG "$OPENWB_USER" | grep -qw gpio 2>/dev/null; then
        sudo groupadd gpio 2>/dev/null || true
        sudo usermod -aG gpio "$OPENWB_USER" 2>/dev/null || true
    fi
}

run_as_openwb_user() {
    if [ "${OPENWB_RUN_AS_USER:-0}" = "1" ]; then
        return 0
    fi
    ensure_openwb_user
    if [ "$(id -un)" = "$OPENWB_USER" ]; then
        export OPENWB_RUN_AS_USER=1
        return 0
    fi
    log "Starte Installer als Benutzer '$OPENWB_USER'..."

    local tmp="/tmp/openwb-trixie-install-$$.sh"
    case "$0" in
        /dev/fd/*|/proc/*)
            curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" \
                "${OPENWB_TRIXIE_URL}?_=$(date +%s)" -o "$tmp"
            ;;
        *)
            if [ -f "$0" ] && [ -r "$0" ]; then
                cp "$0" "$tmp"
            else
                curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" \
                    "${OPENWB_TRIXIE_URL}?_=$(date +%s)" -o "$tmp"
            fi
            ;;
    esac
    chmod a+r "$tmp"
    trap 'rm -f "$tmp"' EXIT
    exec sudo -H -u "$OPENWB_USER" env OPENWB_RUN_AS_USER=1 MODE="$MODE" bash "$tmp" "$@"
}

recover_dpkg_if_needed() {
    if sudo test -n "$(sudo find /var/lib/dpkg/updates -maxdepth 1 -type f 2>/dev/null)"; then
        log_warning "Unvollständiger dpkg-Status, repariere..."
        sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a
    fi
}

configure_german_defaults() {
    log "Setze deutsche Standards (Zeitzone/Locale/Tastatur)..."
    sudo timedatectl set-timezone Europe/Berlin 2>/dev/null || sudo ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
    sudo sh -c 'echo "Europe/Berlin" > /etc/timezone'
    sudo DEBIAN_FRONTEND=noninteractive apt install -y locales keyboard-configuration console-setup tzdata
    if ! grep -q '^de_DE.UTF-8 UTF-8$' /etc/locale.gen; then
        echo 'de_DE.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen > /dev/null
    fi
    sudo locale-gen de_DE.UTF-8
    sudo update-locale LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8
    {
        echo 'keyboard-configuration keyboard-configuration/layoutcode select de'
        echo 'keyboard-configuration keyboard-configuration/modelcode select pc105'
    } | sudo debconf-set-selections
    sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration 2>/dev/null || true
    sudo setupcon -k 2>/dev/null || true
}

configure_gpio() {
    if ! is_arm_arch || ! is_raspberry_pi; then
        log "Kein Raspberry Pi - GPIO-Konfiguration übersprungen"
        return 0
    fi

    local config_txt=""
    if [ -f "/boot/firmware/config.txt" ]; then
        config_txt="/boot/firmware/config.txt"
    elif [ -f "/boot/config.txt" ]; then
        config_txt="/boot/config.txt"
    fi

    if [ -z "$config_txt" ]; then
        log_warning "config.txt nicht gefunden"
        return 0
    fi

    log "Konfiguriere GPIO ($config_txt)..."
    sudo cp "$config_txt" "${config_txt}.backup.$(date +%Y%m%d_%H%M%S)"
    sudo sed -i 's/dtparam=audio=on/dtparam=audio=off/g' "$config_txt"
    sudo sed -i 's/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/g' "$config_txt"

    if ! grep -q "# openwb - begin" "$config_txt"; then
        sudo tee -a "$config_txt" > /dev/null << 'EOF'
# openwb - begin
# openwb-version:4
# Do not edit this section! We need begin/end and version for proper updates!
[all]
gpio=4,5,7,11,17,22,23,24,25,26,27=op,dl
gpio=6,8,9,10,12,13,16,21=ip,pu
[cm4]
gpio=22=op,dh
[all]
dtoverlay=disable-bt
enable_uart=1
avoid_warnings=1
# openwb - end
EOF
        log_success "GPIO-Konfiguration hinzugefügt"
    else
        log "GPIO-Konfiguration bereits vorhanden"
    fi
}

configure_php() {
    local php_ver
    php_ver=$(detect_php_version)
    log "Konfiguriere PHP $php_ver (Upload-Limits 300M)..."
    sudo mkdir -p "/etc/php/$php_ver/apache2/conf.d/" 2>/dev/null || true
    printf 'upload_max_filesize = 300M\npost_max_size = 300M\n' | sudo tee "/etc/php/$php_ver/apache2/conf.d/20-uploadlimit.ini" > /dev/null
}

ensure_mosquitto_local_unit() {
    if [ -f "/etc/systemd/system/mosquitto_local.service" ]; then
        return 0
    fi

    if [ ! -f "/etc/init.d/mosquitto_local" ]; then
        log "Erstelle mosquitto_local Init-Script..."
        sudo tee /etc/init.d/mosquitto_local > /dev/null <<'INITEOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          mosquitto_local
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Mosquitto Local Instance for openWB
### END INIT INFO
PIDFILE=/run/mosquitto_local.pid
CONF=/etc/mosquitto/mosquitto_local.conf

start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "mosquitto_local already running"
        return 0
    fi
    mkdir -p /var/log/openWB
    mosquitto -c "$CONF" -d -p 1885
    pgrep -f "mosquitto.*-p 1885" > "$PIDFILE" 2>/dev/null || true
}

stop() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
}

restart() {
    stop
    sleep 1
    start
}

case "$1" in
    start)   start   ;;
    stop)    stop    ;;
    restart) restart ;;
    *)       echo "Usage: $0 {start|stop|restart}" ;;
esac
INITEOF
        sudo chmod +x /etc/init.d/mosquitto_local
    fi

    if [ ! -f "/etc/mosquitto/mosquitto_local.conf" ]; then
        sudo tee /etc/mosquitto/mosquitto_local.conf > /dev/null <<'CONFEOF'
listener 1885 127.0.0.1
allow_anonymous true
max_keepalive 600
CONFEOF
    fi

    log "Erstelle mosquitto_local systemd Unit..."
    sudo tee /etc/systemd/system/mosquitto_local.service > /dev/null <<'EOF'
[Unit]
Description=Mosquitto Local Instance (openWB)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/etc/init.d/mosquitto_local start
ExecStop=/etc/init.d/mosquitto_local stop
ExecReload=/etc/init.d/mosquitto_local restart
PIDFile=/run/mosquitto_local.pid
TimeoutSec=60
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable mosquitto_local >/dev/null 2>&1 || true
}

# ============================================================================
# Python-Modus: venv (System-Python + Virtual Environment)
# ============================================================================
do_python_venv() {
    log_step "Python venv Setup (System-Python, keine Kompilierung)"

    sudo apt-get install -y python3 python3-venv python3-pip

    local requirements="$SCRIPT_DIR/requirements.txt"
    if [ ! -f "$requirements" ]; then
        log_error "requirements.txt nicht gefunden: $requirements"
        exit 1
    fi

    # venv erstellen oder aktualisieren
    if [ -d "$VENV_DIR" ]; then
        log "venv existiert bereits, aktualisiere..."
    else
        log "Erstelle venv in $VENV_DIR..."
        sudo mkdir -p "$VENV_DIR"
        if id "$OPENWB_USER" &>/dev/null; then
            sudo chown -R "$OPENWB_USER:$OPENWB_USER" "$VENV_DIR"
        fi
        python3 -m venv --system-site-packages "$VENV_DIR"
    fi

    # Systempaket python3-rpi-lgpio (nur Raspberry Pi)
    if is_arm_arch && is_raspberry_pi; then
        if apt-cache show python3-rpi-lgpio >/dev/null 2>&1; then
            sudo apt-get install -y python3-rpi-lgpio
        fi
    fi

    # Pakete installieren
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip setuptools wheel

    local filtered_req
    filtered_req=$(mktemp)
    grep -v '^rpi-lgpio' "$requirements" > "$filtered_req"
    pip install -r "$filtered_req"
    rm -f "$filtered_req"

    pip freeze > "$VENV_DIR/installed_requirements.txt"
    cp "$requirements" "$VENV_DIR/requirements.txt"
    deactivate

    # Wrapper
    sudo tee /usr/local/bin/openwb-activate > /dev/null << 'WRAPPER'
#!/bin/bash
VENV_DIR="/opt/openwb-venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "venv nicht gefunden: $VENV_DIR"
    exit 1
fi
source "$VENV_DIR/bin/activate"
if [ $# -gt 0 ]; then
    "$@"
    exit $?
else
    echo "OpenWB venv aktiviert. Zum Deaktivieren: deactivate"
    exec $SHELL
fi
WRAPPER
    sudo chmod +x /usr/local/bin/openwb-activate

    # asyncio.coroutine Kompatibilitäts-Shim (Python 3.11+)
    local py_ver
    py_ver=$("$VENV_DIR/bin/python3" -c 'import sys; v=sys.version_info; print(f"{v.major}.{v.minor}")' 2>/dev/null || echo "0.0")
    local py_major py_minor
    py_major=$(echo "$py_ver" | cut -d. -f1)
    py_minor=$(echo "$py_ver" | cut -d. -f2)

    if [ "$py_major" -ge 3 ] && [ "$py_minor" -ge 11 ]; then
        local shim_dir="$VENV_DIR/lib/python${py_major}.${py_minor}/site-packages"
        if [ ! -f "$shim_dir/openwb_py313_compat.py" ]; then
            log "Installiere asyncio.coroutine Shim (Python ${py_major}.${py_minor})..."
            sudo mkdir -p "$shim_dir"
            sudo tee "$shim_dir/openwb_py313_compat.py" > /dev/null << 'PYEOF'
import asyncio
import types
import sys
if sys.version_info >= (3, 11) and not hasattr(asyncio, "coroutine"):
    def _coroutine_compat(func):
        return types.coroutine(func)
    asyncio.coroutine = _coroutine_compat
PYEOF
            echo "import openwb_py313_compat" | sudo tee "$shim_dir/openwb_py313_compat.pth" > /dev/null
            sudo chown "$OPENWB_USER:$OPENWB_USER" "$shim_dir/openwb_py313_compat.py" "$shim_dir/openwb_py313_compat.pth" 2>/dev/null || true
            log_success "asyncio.coroutine Shim installiert"
        fi
    fi

    # Config
    sudo tee "$VENV_DIR/.openwb-venv-config" > /dev/null << EOF
VENV_VERSION_INSTALLED="1.0.0"
VENV_CREATED="$(date +'%Y-%m-%d %H:%M:%S')"
VENV_PYTHON_VERSION="$(python3 --version 2>&1 | awk '{print $2}')"
VENV_DIR="$VENV_DIR"
EOF
    if id "$OPENWB_USER" &>/dev/null; then
        sudo chown -R "$OPENWB_USER:$OPENWB_USER" "$VENV_DIR"
    fi

    log_success "venv erstellt mit Python $($VENV_DIR/bin/python3 --version 2>&1 | awk '{print $2}')"
}

# ============================================================================
# Python-Modus: Python 3.9.25 kompilieren (Legacy, Original-System)
# ============================================================================
do_python_39() {
    log_step "Python 3.9.25 Kompilierung (Legacy-Modus, 30-60 Min)"

    log_warning "Dies überschreibt das System-Python mit Python 3.9.25!"
    log_warning "Dauer: 30-60 Minuten je nach Hardware"
    echo ""

    if [ "$NONINTERACTIVE" -ne 1 ]; then
        read -p "Wirklich fortfahren? (j/N): " -n 1 -r < /dev/tty
        echo
        if [[ ! "$REPLY" =~ ^[JjYy]$ ]]; then
            log "Abgebrochen"
            exit 0
        fi
    fi

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        vim bc jq socat sshpass sudo ssl-cert \
        apache2 libapache2-mod-php php php-gd php-curl php-xml php-json \
        git mosquitto mosquitto-clients python3-pip \
        build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
        libnss3-dev libssl-dev libsqlite3-dev libreadline-dev libffi-dev \
        libbz2-dev liblzma-dev libgdbm-compat-dev libdb5.3-dev \
        uuid-dev tk-dev libexpat1-dev libmpdec-dev \
        wget curl make gcc g++ pkg-config \
        libxml2-dev libxslt1-dev

    if is_arm_arch && is_raspberry_pi; then
        if apt-cache show liblgpio-dev >/dev/null 2>&1; then
            sudo apt-get install -y liblgpio-dev
        fi
    fi

    log "Lade Python 3.9.25 Quellcode..."
    cd /tmp
    wget -q https://www.python.org/ftp/python/3.9.25/Python-3.9.25.tar.xz
    tar -xJf Python-3.9.25.tar.xz
    cd Python-3.9.25

    log "Konfiguriere Python 3.9.25..."
    ./configure \
        --enable-optimizations \
        --with-ensurepip=install \
        --enable-shared \
        --enable-loadable-sqlite-extensions \
        --with-system-expat \
        --with-system-ffi

    _compile

    log "Installiere Python 3.9.25 (ersetzt System-Python)..."
    sudo make install
    sudo ldconfig
    sudo ln -sf /usr/local/bin/python3 /usr/local/bin/python
    sudo ln -sf /usr/local/bin/pip3 /usr/local/bin/pip

    /usr/local/bin/pip3 install rpi-lgpio 2>/dev/null || true

    cd /
    rm -rf /tmp/Python-3.9.25*

    log_success "Python 3.9.25 installiert: $(python3 --version 2>&1)"
}

# ============================================================================
# Python-Modus: Python 3.14.4 kompilieren + venv (neuestes Python)
# ============================================================================
PYTHON_314_VERSION="3.14.4"
PYTHON_314_DIR="/opt/python${PYTHON_314_VERSION}"

do_python_314() {
    log_step "Python ${PYTHON_314_VERSION} kompilieren + venv (30-60 Min)"

    log "Kompiliert Python ${PYTHON_314_VERSION} als ZUSÄTZLICHE Installation"
    log "System-Python bleibt UNVERÄNDERT, venv nutzt das neue Python"
    log_warning "Dauer: 30-60 Minuten je nach Hardware"
    echo ""

    if [ "$NONINTERACTIVE" -ne 1 ]; then
        read -p "Fortfahren? (j/N): " -n 1 -r < /dev/tty
        echo
        if [[ ! "$REPLY" =~ ^[JjYy]$ ]]; then
            log "Abgebrochen"
            exit 0
        fi
    fi

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
        libnss3-dev libssl-dev libsqlite3-dev libreadline-dev libffi-dev \
        libbz2-dev liblzma-dev libgdbm-compat-dev libdb5.3-dev \
        uuid-dev tk-dev libexpat1-dev libmpdec-dev \
        wget curl make gcc g++ pkg-config \
        libxml2-dev libxslt1-dev

    # Prüfe ob bereits kompiliert
    if [ -x "$PYTHON_314_DIR/bin/python3" ]; then
        log_success "Python ${PYTHON_314_VERSION} bereits kompiliert: $($PYTHON_314_DIR/bin/python3 --version 2>&1)"
    else
        log "Lade Python ${PYTHON_314_VERSION} Quellcode..."
        cd /tmp
        wget -q "https://www.python.org/ftp/python/${PYTHON_314_VERSION}/Python-${PYTHON_314_VERSION}.tar.xz"
        tar -xJf "Python-${PYTHON_314_VERSION}.tar.xz"
        cd "Python-${PYTHON_314_VERSION}"

        log "Konfiguriere Python ${PYTHON_314_VERSION}..."
        ./configure \
            --prefix="$PYTHON_314_DIR" \
            --enable-optimizations \
            --with-ensurepip=install \
            --enable-shared \
            --enable-loadable-sqlite-extensions \
            --with-system-expat \
            --with-system-ffi

        _compile

        log "Installiere Python ${PYTHON_314_VERSION} nach $PYTHON_314_DIR (altinstall)..."
        sudo make install

        # Shared Library Pfad
        echo "$PYTHON_314_DIR/lib" | sudo tee /etc/ld.so.conf.d/python${PYTHON_314_VERSION}.conf > /dev/null
        sudo ldconfig

        cd /
        rm -rf "/tmp/Python-${PYTHON_314_VERSION}"*

        log_success "Python ${PYTHON_314_VERSION} kompiliert: $($PYTHON_314_DIR/bin/python3 --version 2>&1)"
    fi

    # venv aus dem kompilierten Python erstellen
    log "Erstelle venv aus Python ${PYTHON_314_VERSION}..."
    if [ -d "$VENV_DIR" ]; then
        log "venv existiert, aktualisiere..."
    else
        sudo mkdir -p "$VENV_DIR"
    fi

    "$PYTHON_314_DIR/bin/python3" -m venv --clear "$VENV_DIR"

    if id "$OPENWB_USER" &>/dev/null; then
        sudo chown -R "$OPENWB_USER:$OPENWB_USER" "$VENV_DIR"
    fi

    # Pakete installieren
    local requirements="$SCRIPT_DIR/requirements.txt"
    if [ -f "$requirements" ]; then
        source "$VENV_DIR/bin/activate"
        pip install --upgrade pip setuptools wheel
        local filtered_req
        filtered_req=$(mktemp)
        grep -v '^rpi-lgpio' "$requirements" > "$filtered_req"
        pip install -r "$filtered_req"
        rm -f "$filtered_req"
        pip freeze > "$VENV_DIR/installed_requirements.txt"
        cp "$requirements" "$VENV_DIR/requirements.txt"
        deactivate
    fi

    # Systempaket python3-rpi-lgpio (nur Raspberry Pi)
    if is_arm_arch && is_raspberry_pi; then
        if apt-cache show python3-rpi-lgpio >/dev/null 2>&1; then
            sudo apt-get install -y python3-rpi-lgpio
        fi
    fi

    # asyncio.coroutine Shim (nicht nötig für 3.14, aber sicherheitshalber)
    local py_ver
    py_ver=$("$VENV_DIR/bin/python3" -c 'import sys; v=sys.version_info; print(f"{v.major}.{v.minor}")' 2>/dev/null || echo "0.0")
    local py_major py_minor
    py_major=$(echo "$py_ver" | cut -d. -f1)
    py_minor=$(echo "$py_ver" | cut -d. -f2)
    local shim_dir="$VENV_DIR/lib/python${py_major}.${py_minor}/site-packages"
    if [ "$py_major" -ge 3 ] && [ "$py_minor" -ge 11 ] && [ ! -f "$shim_dir/openwb_py313_compat.py" ]; then
        sudo mkdir -p "$shim_dir"
        sudo tee "$shim_dir/openwb_py313_compat.py" > /dev/null << 'PYEOF'
import asyncio
import types
import sys
if sys.version_info >= (3, 11) and not hasattr(asyncio, "coroutine"):
    def _coroutine_compat(func):
        return types.coroutine(func)
    asyncio.coroutine = _coroutine_compat
PYEOF
        echo "import openwb_py313_compat" | sudo tee "$shim_dir/openwb_py313_compat.pth" > /dev/null
    fi

    # Wrapper
    sudo tee /usr/local/bin/openwb-activate > /dev/null << 'WRAPPER'
#!/bin/bash
VENV_DIR="/opt/openwb-venv"
if [ ! -d "$VENV_DIR" ]; then echo "venv nicht gefunden"; exit 1; fi
source "$VENV_DIR/bin/activate"
if [ $# -gt 0 ]; then "$@"; exit $?; fi
echo "OpenWB venv aktiviert. Deaktivieren: deactivate"
exec $SHELL
WRAPPER
    sudo chmod +x /usr/local/bin/openwb-activate

    # Config
    sudo tee "$VENV_DIR/.openwb-venv-config" > /dev/null << EOF
VENV_VERSION_INSTALLED="1.0.0"
VENV_CREATED="$(date +'%Y-%m-%d %H:%M:%S')"
VENV_PYTHON_VERSION="$($PYTHON_314_DIR/bin/python3 --version 2>&1 | awk '{print $2}')"
VENV_DIR="$VENV_DIR"
VENV_COMPILED_PYTHON="$PYTHON_314_DIR"
EOF
    if id "$OPENWB_USER" &>/dev/null; then
        sudo chown -R "$OPENWB_USER:$OPENWB_USER" "$VENV_DIR"
    fi

    log_success "venv erstellt mit Python $($VENV_DIR/bin/python3 --version 2>&1 | awk '{print $2}')"
}

# Kompilierungs-Helper (gemeinsam für 3.9 und 3.14)
_compile() {
    local available_ram cpu_cores jobs
    available_ram=$(free -g | awk 'NR==2{print $7}')
    cpu_cores=$(nproc)
    if [ "${available_ram:-0}" -lt 2 ]; then
        jobs=1
    elif [ "${available_ram:-0}" -lt 4 ]; then
        jobs=2
    else
        jobs=$((cpu_cores > 4 ? 4 : cpu_cores))
    fi
    log "Kompiliere mit $jobs Jobs (RAM: ${available_ram:-?}GB, Cores: $cpu_cores)..."
    make -j"$jobs"
}

# ============================================================================
# OpenWB Installation (gemeinsam für beide Modi)
# ============================================================================
do_openwb_install() {
    log_step "OpenWB Installation"

    if [ -f "$OPENWB_DIR/openwb.sh" ]; then
        log "OpenWB bereits installiert, überspringe"
        return 0
    fi

    ensure_free_space_mb 2500
    sudo mkdir -p /var/www/html
    sudo chown root:root /var/www /var/www/html 2>/dev/null || true

    local tmp_dir install_script packages_script
    tmp_dir=$(mktemp -d)
    install_script="$tmp_dir/openwb-install.sh"
    packages_script="$tmp_dir/install_packages.sh"
    trap 'rm -rf "$tmp_dir"' RETURN

    log "Lade OpenWB Installer..."
    curl -fsSL https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh -o "$install_script"
    curl -fsSL https://raw.githubusercontent.com/openWB/core/master/runs/install_packages.sh -o "$packages_script"

    # Upstream-Skripte robuster machen
    sed -i \
        -e 's|sudo apt-get -q update|sudo DEBIAN_FRONTEND=noninteractive apt-get -q update|g' \
        -e 's|sudo apt-get -q -y install|sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install|g' \
        "$packages_script"

    # pip-Aufrufe auf venv umleiten (falls venv-Modus)
    if [ "$MODE" = "venv" ] || [ "$MODE" = "python314" ]; then
        sed -i \
            -e "s@curl -s \"https://raw.githubusercontent.com/openWB/core/master/runs/install_packages.sh\" | bash -s@bash \"$packages_script\"@g" \
            -e 's@mkdir "$OPENWBBASEDIR"@mkdir -p "$OPENWBBASEDIR"@g' \
            -e "s@sudo -u \"\\\$OPENWB_USER\" pip install -r \"\\\${OPENWBBASEDIR}/requirements.txt\"@/opt/openwb-venv/bin/pip3 install -U pip setuptools wheel; /opt/openwb-venv/bin/pip3 install -r \"\\\${OPENWBBASEDIR}/requirements.txt\"@g" \
            -e 's@^/usr/sbin/groupadd "\$OPENWB_GROUP"$@/usr/sbin/groupadd "$OPENWB_GROUP" || true@g' \
            -e 's@^/usr/sbin/useradd "\$OPENWB_USER" -g "\$OPENWB_GROUP" --create-home$@/usr/sbin/useradd "$OPENWB_USER" -g "$OPENWB_GROUP" --create-home || true@g' \
            -e 's@^ln -s "\${OPENWBBASEDIR}/data/config/openwb2.service"@ln -sfn "${OPENWBBASEDIR}/data/config/openwb2.service"@g' \
            -e 's@^ln -s "\${OPENWBBASEDIR}/data/config/openwb-simpleAPI.service"@ln -sfn "${OPENWBBASEDIR}/data/config/openwb-simpleAPI.service"@g' \
            "$install_script"

        sed -E -i \
            -e "s@(^[[:space:]]*sudo -u \"\\\$OPENWB_USER\"[[:space:]]+)pip([[:space:]]+install[[:space:]]+-r[[:space:]]+)@/opt/openwb-venv/bin/pip3\\2@g" \
            -e "s@(^[[:space:]]*)pip([[:space:]]+install[[:space:]]+-r[[:space:]]+)@/opt/openwb-venv/bin/pip3\\2@g" \
            "$install_script"
    else
        sed -i \
            -e "s@curl -s \"https://raw.githubusercontent.com/openWB/core/master/runs/install_packages.sh\" | bash -s@bash \"$packages_script\"@g" \
            -e 's@mkdir "$OPENWBBASEDIR"@mkdir -p "$OPENWBBASEDIR"@g' \
            -e 's@^/usr/sbin/groupadd "\$OPENWB_GROUP"$@/usr/sbin/groupadd "$OPENWB_GROUP" || true@g' \
            -e 's@^/usr/sbin/useradd "\$OPENWB_USER" -g "\$OPENWB_GROUP" --create-home$@/usr/sbin/useradd "$OPENWB_USER" -g "$OPENWB_GROUP" --create-home || true@g' \
            "$install_script"
    fi

    sed -i '2i set -Eeuo pipefail' "$install_script"

    log "Führe OpenWB Installer aus..."
    sudo DEBIAN_FRONTEND=noninteractive bash "$install_script"
    log_success "OpenWB installiert"
}

# ============================================================================
# Runtime Patches (modus-abhängig)
# ============================================================================
do_runtime_patches() {
    if [ ! -d "$OPENWB_DIR" ]; then
        log_warning "OpenWB-Verzeichnis nicht gefunden, überspringe Runtime-Patches"
        return 0
    fi

    log_step "Runtime Patches"

    local atreboot="$OPENWB_DIR/runs/atreboot.sh"
    local service="$OPENWB_DIR/data/config/openwb2.service"
    local simpleapi="$OPENWB_DIR/data/config/openwb-simpleAPI.service"
    local remote_service="/etc/systemd/system/openwbRemoteSupport.service"

    # Services stoppen
    for svc in openwb2 openwb; do
        if systemctl is-active "$svc" &>/dev/null; then
            sudo systemctl stop "$svc" 2>/dev/null || true
        fi
    done

    if [ "$MODE" = "venv" ] || [ "$MODE" = "python314" ]; then
        local venv_python="$VENV_DIR/bin/python3"
        local venv_pip="$VENV_DIR/bin/pip3"

        # openwb2.service
        if [ -f "$service" ]; then
            log "Patche openwb2.service -> venv Python..."
            sudo sed -i "s#^ExecStart=.*main.py#ExecStart=$venv_python $OPENWB_DIR/packages/main.py#g" "$service"
        fi

        # simpleAPI.service
        if [ -f "$simpleapi" ]; then
            log "Patche simpleAPI.service -> venv Python..."
            sudo sed -i -E 's@^ExecStart=.*simpleAPI_mqtt\.py$@ExecStart=/opt/openwb-venv/bin/python3 /var/www/html/openWB/simpleAPI/simpleAPI_mqtt.py@g' "$simpleapi"
            sudo ln -sfn "$simpleapi" /etc/systemd/system/openwb-simpleAPI.service
        fi

        # remoteSupport.service
        if [ -f "$remote_service" ]; then
            sudo sed -i "s#^ExecStart=.*#ExecStart=$venv_python $OPENWB_DIR/runs/remoteSupport/remoteSupport.py#g" "$remote_service"
        fi

        # atreboot.sh: Alle pip3 Aufrufe -> venv pip
        if [ -f "$atreboot" ]; then
            log "Patche atreboot.sh -> venv pip..."
            sudo sed -i -E 's@(^|[^[:alnum:]_/.-])pip3[[:space:]]+install[[:space:]]+-r@\1/opt/openwb-venv/bin/pip3 install -r@g' "$atreboot"
            sudo sed -i -E 's@(^|[^[:alnum:]_/.-])pip3[[:space:]]+install[[:space:]]+--only-binary@\1/opt/openwb-venv/bin/pip3 install --only-binary@g' "$atreboot"
            sudo sed -i 's|pip uninstall urllib3 -y|/opt/openwb-venv/bin/pip3 uninstall urllib3 -y|g' "$atreboot"
            sudo chmod +x "$atreboot"
        fi

        # requirements.txt für Python 3.13 patchen
        local req="$OPENWB_DIR/requirements.txt"
        if [ -f "$req" ]; then
            log "Patche requirements.txt für Python 3.13..."
            sudo sed -E -i \
                -e 's/^jq==[0-9]+\.[0-9]+\.[0-9]+([[:space:]]*)$/# jq entfernt (System-jq via apt)\1/' \
                -e 's/^lxml==4\.9\.[0-9]+([[:space:]]*)$/lxml==5.3.2\1/' \
                -e 's/^grpcio==1\.60\.1([[:space:]]*)$/grpcio==1.71.0\1/' \
                "$req"
        fi
    fi

    # mosquitto_local systemd Unit (für beide Modi)
    ensure_mosquitto_local_unit

    sudo systemctl daemon-reload
    log_success "Runtime Patches angewendet"
}

# ============================================================================
# Post-Update Hook installieren
# ============================================================================
do_post_update_hook() {
    log_step "Post-Update Hook"

    local hook_src="$SCRIPT_DIR/openwb_post_update_hook.sh"
    if [ ! -f "$hook_src" ]; then
        log_warning "post-update hook nicht gefunden: $hook_src"
        return 0
    fi

    sudo mkdir -p "$OPENWB_DIR/data/config"
    sudo cp "$hook_src" "$OPENWB_DIR/data/config/post-update.sh"
    sudo chmod +x "$OPENWB_DIR/data/config/post-update.sh"
    log_success "Post-Update Hook installiert"
}

# ============================================================================
# Feature-Patches (modular, update-sicher, einzeln an-/abwählbar)
# ============================================================================
PATCHES_SRC_DIR=""  # wird in main() auf das repo-Verzeichnis gesetzt

patches_discover() {
    local pdir="$1"
    local patches=()
    for f in "$pdir"/*.sh; do
        [ -f "$f" ] || continue
        local basename
        basename=$(basename "$f")
        patches+=("$basename")
    done
    printf '%s\n' "${patches[@]}" | sort
}

patch_get_field() {
    local file="$1" field="$2"
    grep -m1 "^# $field:" "$file" 2>/dev/null | sed "s/^# $field: *//"
}

patches_load_enabled() {
    if [ ! -d "$PATCH_DIR" ]; then
        sudo mkdir -p "$PATCH_DIR"
        sudo chown "$(id -un):$(id -un)" "$PATCH_DIR" 2>/dev/null || true
    fi
    [ -f "$PATCH_CONF" ] || touch "$PATCH_CONF"
}

patch_is_enabled() {
    local pid="$1"
    grep -qx "$pid" "$PATCH_CONF" 2>/dev/null
}

patch_enable() {
    local pid="$1"
    patches_load_enabled
    if ! patch_is_enabled "$pid"; then
        echo "$pid" >> "$PATCH_CONF"
    fi
}

patch_disable() {
    local pid="$1"
    [ -f "$PATCH_CONF" ] || return
    sed -i "/^${pid}$/d" "$PATCH_CONF"
}

patches_apply_enabled() {
    patches_load_enabled
    [ -s "$PATCH_CONF" ] || return 0

    log "Wende aktivierte Feature-Patches an..."
    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        local pfile=""
        for f in "$PATCHES_SRC_DIR"/patches/*.sh; do
            [ -f "$f" ] || continue
            if [ "$(patch_get_field "$f" "Id")" = "$pid" ]; then
                pfile="$f"
                break
            fi
        done
        if [ -z "$pfile" ]; then
            log_warning "Patch '$pid' nicht gefunden (überspringe)"
            continue
        fi
        export OPENWB_DIR VENV_DIR
        source "$pfile"
        if patch_check; then
            log "  $pid: bereits aktiv"
        else
            if patch_apply; then
                log_success "  $pid: angewendet"
            else
                log_error "  $pid: FEHLER"
            fi
        fi
    done < "$PATCH_CONF"
}

patches_menu() {
    if [ ! -d "$PATCHES_SRC_DIR/patches" ]; then
        return 0
    fi

    local available
    available=$(patches_discover "$PATCHES_SRC_DIR/patches")
    [ -n "$available" ] || return 0

    patches_load_enabled

    local BOLD='\033[1m' DIM='\033[2m' W='\033[0m'
    local GR='\033[0;32m' BG='\033[1;32m' BB='\033[1;34m'
    local BY='\033[1;33m' RED='\033[0;31m' CY='\033[0;36m'

    while true; do
        local count=0
        local patch_ids=()

        echo ""
        echo -e "  ${BB}┌──────────────────────────────────────────────────────────┐${W}"
        echo -e "  ${BB}│${W}          ${BOLD}Feature-Patches (update-sicher)${W}                        ${BB}│${W}"
        echo -e "  ${BB}├──────────────────────────────────────────────────────────┤${W}"

        while IFS= read -r pfile; do
            [ -z "$pfile" ] && continue
            local full="$PATCHES_SRC_DIR/patches/$pfile"
            local pid name desc
            pid=$(patch_get_field "$full" "Id")
            name=$(patch_get_field "$full" "Name")
            desc=$(patch_get_field "$full" "Desc")
            [ -z "$pid" ] && continue

            count=$((count + 1))
            patch_ids+=("$pid")

            if patch_is_enabled "$pid"; then
                echo -e "  ${BB}│${W}  ${GR}[${count}] INSTALLED${W}  ${BOLD}${name}${W}"
            else
                echo -e "  ${BB}│${W}  ${BY}[${count}] verfügbar${W}   ${name}${W}"
            fi
            echo -e "  ${BB}│${W}       ${DIM}${desc}${W}"
        done <<< "$available"

        echo -e "  ${BB}│${W}                                                          ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${DIM}[0] Weiter / Fertig${W}                                  ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${DIM}[r] Patch entfernen${W}                                   ${BB}│${W}"
        echo -e "  ${BB}└──────────────────────────────────────────────────────────┘${W}"
        echo ""

        echo -ne "  ${BOLD}Wahl${W} [0-${count}/r]: "
        read -n 1 -r < /dev/tty
        echo

        case "$REPLY" in
            0|"") break ;;
            r|R)
                echo -ne "  Patch-Nummer zum ${RED}Entfernen${W}: "
                read -r num < /dev/tty
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$count" ]; then
                    local pid="${patch_ids[$((num-1))]}"
                    local full="$PATCHES_SRC_DIR/patches/$(ls "$PATCHES_SRC_DIR/patches/" | sed -n "${num}p")"
                    export OPENWB_DIR VENV_DIR
                    source "$full"
                    if patch_revert; then
                        patch_disable "$pid"
                        log_success "Patch '$pid' entfernt und deaktiviert"
                    else
                        log_error "Patch '$pid' konnte nicht entfernt werden"
                    fi
                else
                    echo -e "  ${RED}Ungültige Nummer${W}"
                fi
                continue
                ;;
        esac

        if [[ "$REPLY" =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$count" ]; then
            local pid="${patch_ids[$((REPLY-1))]}"
            local full="$PATCHES_SRC_DIR/patches/$(ls "$PATCHES_SRC_DIR/patches/" | sed -n "${REPLY}p")"
            export OPENWB_DIR VENV_DIR
            source "$full"

            if patch_is_enabled "$pid"; then
                echo -e "  ${GR}Patch '$pid' ist bereits installiert.${W}"
                echo -ne "  Entfernen? (j/N): "
                read -n 1 -r yn < /dev/tty
                echo
                if [[ "$yn" =~ ^[JjYy]$ ]]; then
                    if patch_revert; then
                        patch_disable "$pid"
                        log_success "Patch '$pid' entfernt und deaktiviert"
                    fi
                fi
            else
                echo -e "  Installiere '${BOLD}$(patch_get_field "$full" "Name")${W}'..."
                if patch_apply; then
                    patch_enable "$pid"
                    log_success "Patch '$pid' installiert und aktiviert"
                else
                    log_error "Patch '$pid' konnte nicht installiert werden"
                fi
            fi
        fi
    done
}

# ============================================================================
# Finale Überprüfung
# ============================================================================
do_final_check() {
    log_step "Überprüfung"

    local BOLD='\033[1m' DIM='\033[2m' W='\033[0m'
    local GR='\033[0;32m' BG='\033[1;32m' BB='\033[1;34m'
    local BY='\033[1;33m' RED='\033[0;31m' CY='\033[0;36m'

    echo ""
    echo -e "  ${BB}┌─────────────────────────────────────────────────────────┐${W}"
    echo -e "  ${BB}│${W}       ${BG}OpenWB Trixie — Installation abgeschlossen${W}          ${BB}│${W}"
    echo -e "  ${BB}├─────────────────────────────────────────────────────────┤${W}"

    local deb_ver
    deb_ver=$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-${VERSION:-?}}" || echo "?")
    echo -e "  ${BB}│${W}  ${BOLD}Debian:${W}       $deb_ver"
    echo -e "  ${BB}│${W}  ${BOLD}Architektur:${W}  $(uname -m)$(is_raspberry_pi && echo " ${CY}(Raspberry Pi)${W}" || true)"

    case "$MODE" in
        venv|python314)
            echo -e "  ${BB}│${W}  ${BOLD}Python:${W}       ${GR}$(python3 --version 2>&1 | awk '{print $2}')${W} (System)"
            echo -e "  ${BB}│${W}  ${BOLD}venv:${W}         ${BG}$($VENV_DIR/bin/python3 --version 2>&1 | awk '{print $2}')${W} ($VENV_DIR)"
            ;;
        python39)
            echo -e "  ${BB}│${W}  ${BOLD}Python:${W}       ${GR}$(python3 --version 2>&1 | awk '{print $2}')${W} (kompiliert)"
            ;;
    esac

    echo -e "  ${BB}│${W}  ${BOLD}Post-Update:${W}  ${GR}installiert${W}"
    echo -e "  ${BB}├─────────────────────────────────────────────────────────┤${W}"
    echo -e "  ${BB}│${W}  ${BOLD}Services:${W}"

    for svc in mosquitto mosquitto_local openwb2 openwb-simpleAPI apache2; do
        local status
        status=$(systemctl is-active "$svc" 2>/dev/null || echo "?")
        if [ "$status" = "active" ]; then
            echo -e "  ${BB}│${W}    ${GR}OK${W}    $svc"
        else
            echo -e "  ${BB}│${W}    ${RED}$status${W}  $svc"
        fi
    done

    echo -e "  ${BB}├─────────────────────────────────────────────────────────┤${W}"
    echo -e "  ${BB}│${W}  ${BOLD}Web-Interface:${W}  ${CY}http://$(hostname -I 2>/dev/null | awk '{print $1}')${W}"

    if [ -f "$PATCH_CONF" ] && [ -s "$PATCH_CONF" ]; then
        echo -e "  ${BB}│${W}  ${BOLD}Feature-Patches:${W}"
        while IFS= read -r pid; do
            [ -z "$pid" ] && continue
            echo -e "  ${BB}│${W}    ${GR}aktiv${W}  $pid"
        done < "$PATCH_CONF"
    fi

    echo -e "  ${BB}│${W}"
    if is_arm_arch && is_raspberry_pi; then
        echo -e "  ${BB}│${W}  ${BY}WICHTIG: Bitte zuerst rebooten fuer GPIO-Konfiguration!${W}"
        echo -e "  ${BB}│${W}           ${BOLD}sudo reboot${W}"
        echo -e "  ${BB}│${W}"
    fi
    echo -e "  ${BB}│${W}  Danach: Im Browser oeffnen und OpenWB konfigurieren"
    echo -e "  ${BB}└─────────────────────────────────────────────────────────┘${W}"
    echo ""
}

# ============================================================================
# HAUPTPROGRAMM
# ============================================================================
main() {
    local BOLD='\033[1m'
    local DIM='\033[2m'
    local W='\033[0m'       # White/Reset
    local GR='\033[0;32m'   # Green
    local BG='\033[1;32m'   # Bold Green
    local CY='\033[0;36m'   # Cyan
    local BY='\033[1;33m'   # Bold Yellow
    local YB='\033[43;1;30m' # Yellow bg, Black text
    local BB='\033[1;34m'   # Bold Blue

    echo ""
    echo -e "  ${BB}╔═══════════════════════════════════════════════════════════╗${W}"
    echo -e "  ${BB}║${W}                                                           ${BB}║${W}"
    echo -e "  ${BB}║${W}        ${BOLD}OpenWB  ·  Debian Trixie Installer${W}                ${BB}║${W}"
    echo -e "  ${BB}║${W}                 ${DIM}v${INSTALLER_VERSION}${W}                              ${BB}║${W}"
    echo -e "  ${BB}║${W}                                                           ${BB}║${W}"
    echo -e "  ${BB}╚═══════════════════════════════════════════════════════════╝${W}"
    echo ""

    if ! is_trixie; then
        log_error "Dies ist KEIN Debian Trixie System!"
        log_error "Bitte zuerst Debian Trixie installieren."
        echo ""
        echo "Download: https://www.debian.org/devel/"
        exit 1
    fi
    log_success "Debian Trixie erkannt (${BOLD}$(cat /etc/debian_version 2>/dev/null || echo "?")${W})"
    log "Architektur: ${BOLD}$(uname -m)${W}$(is_raspberry_pi && echo " ${GR}(Raspberry Pi)${W}" || true)"

    if [ -z "$MODE" ]; then
        local sys_py
        sys_py=$(python3 --version 2>&1 | awk '{print $2}')

        echo ""
        echo -e "  ${BB}┌──────────────────────────────────────────────────────────┐${W}"
        echo -e "  ${BB}│${W}              ${BOLD}Was möchtest du tun?${W}                                ${BB}│${W}"
        echo -e "  ${BB}├──────────────────────────────────────────────────────────┤${W}"
        echo -e "  ${BB}│${W}                                                          ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${BY} [1]${W}  ${BOLD}System-Python + venv${W}                   ${BG}EMPFOHLEN${W}   ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${CY}Python ${sys_py}${W} · Pakete isoliert im venv               ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${GR}System bleibt unangetastet${W}                              ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${DIM}Dauer: ca. 10-15 Minuten${W}                               ${BB}│${W}"
        echo -e "  ${BB}│${W}                                                          ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${BY} [2]${W}  ${BOLD}Python 3.9.25 kompilieren${W}               ${YB}ORIGINAL${W}    ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${CY}Kompiliert aus Quellcode${W}                                ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${RED}Ersetzt System-Python!${W} · Keine Code-Patches nötig       ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${DIM}Dauer: ca. 30-60 Minuten${W}                               ${BB}│${W}"
        echo -e "  ${BB}│${W}                                                          ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${BY} [3]${W}  ${BOLD}Python 3.14.4 kompilieren + venv${W}        ${CY}NEUESTE${W}     ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${CY}Neuestes Python als Zusatz-Installation${W}                 ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${GR}System-Python bleibt unverändert${W}                        ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${DIM}Dauer: ca. 30-60 Minuten${W}                               ${BB}│${W}"
        echo -e "  ${BB}│${W}                                                          ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${BY} [4]${W}  ${BOLD}Feature-Patches verwalten${W}                             ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${DIM}Patches installieren / entfernen${W}                       ${BB}│${W}"
        echo -e "  ${BB}│${W}      ${DIM}(OpenWB muss bereits installiert sein)${W}                ${BB}│${W}"
        echo -e "  ${BB}│${W}                                                          ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${DIM} [5]  Beenden${W}                              ${DIM}build:${BUILD_ID}${W} ${BB}│${W}"
        echo -e "  ${BB}│${W}                                                          ${BB}│${W}"
        echo -e "  ${BB}└──────────────────────────────────────────────────────────┘${W}"
        echo ""
        if [ "$NONINTERACTIVE" -eq 1 ]; then
            log_warning "Non-interactive Modus: wähle Option 1"
            MODE="venv"
        else
            while true; do
                echo -ne "  ${BOLD}Deine Wahl${W} [${BG}1${W}/${BY}2${W}/${CY}3${W}/${BY}4${W}/${DIM}5${W}]: "
                read -n 1 -r < /dev/tty
                echo
                case "$REPLY" in
                    1|"") MODE="venv";      break ;;
                    2)    MODE="python39";   break ;;
                    3)    MODE="python314";  break ;;
                    4)    MODE="patches";    break ;;
                    5|q|Q) echo -e "  ${DIM}Tschüss!${W}"; exit 0 ;;
                    *)    echo -e "  ${RED}Bitte 1-5 eingeben${W}" ;;
                esac
            done
        fi
    fi

    echo ""
    case "$MODE" in
        venv)       echo -e "  ${BG}Ausgewählt: Option 1 — System-Python + venv${W}" ;;
        python39)   echo -e "  ${BY}Ausgewählt: Option 2 — Python 3.9.25 kompilieren (original-getreu)${W}" ;;
        python314)  echo -e "  ${CY}Ausgewählt: Option 3 — Python 3.14.4 kompilieren + venv${W}" ;;
        patches)    echo -e "  ${BY}Ausgewählt: Option 4 — Feature-Patches verwalten${W}" ;;
    esac
    echo ""

    # Option 4: Nur Patch-Verwaltung
    if [ "$MODE" = "patches" ]; then
        if [ ! -d "$OPENWB_DIR" ]; then
            log_error "OpenWB ist noch nicht installiert! Bitte zuerst Option 1, 2 oder 3 ausführen."
            exit 1
        fi

        mkdir -p "$PATCH_DIR"
        chown "$OPENWB_USER:$OPENWB_USER" "$PATCH_DIR" 2>/dev/null || true
        touch "$PATCH_CONF" 2>/dev/null || true
        chown "$OPENWB_USER:$OPENWB_USER" "$PATCH_CONF" 2>/dev/null || true

        run_as_openwb_user

        if [ -d "/home/$OPENWB_USER/openwb-trixie" ]; then
            cd "/home/$OPENWB_USER/openwb-trixie"
            PATCHES_SRC_DIR="$(pwd)"
        elif [ -d "$SCRIPT_DIR/patches" ]; then
            PATCHES_SRC_DIR="$SCRIPT_DIR"
        else
            log "Klone Repository für Patch-Dateien..."
            cd "/home/$OPENWB_USER"
            git clone https://github.com/Xerolux/openwb-trixie.git
            cd openwb-trixie
            PATCHES_SRC_DIR="$(pwd)"
        fi

        patches_apply_enabled
        patches_menu
        echo ""
        log_success "Fertig!"
        exit 0
    fi

    # Als openwb-User ausführen
    run_as_openwb_user

    # ── Schritt 1: System aktualisieren ──
    log_step "Schritt 1/8: System aktualisieren"
    recover_dpkg_if_needed
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

    # ── Schritt 2: Deutsche Standards ──
    log_step "Schritt 2/8: Deutsche Standards"
    configure_german_defaults

    # ── Schritt 3: Build-Abhängigkeiten ──
    log_step "Schritt 3/8: Abhängigkeiten installieren"
    recover_dpkg_if_needed
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        swig build-essential python3-dev python3-pip python3-venv \
        pkg-config libffi-dev libxml2-dev libxslt1-dev zlib1g-dev \
        git curl wget usbutils dnsmasq inotify-tools \
        apache2 libapache2-mod-php php php-gd php-curl php-xml php-json \
        mosquitto mosquitto-clients

    if is_arm_arch && is_raspberry_pi; then
        sudo DEBIAN_FRONTEND=noninteractive apt install -y libgpiod-dev 2>/dev/null || true
        if apt-cache show liblgpio-dev >/dev/null 2>&1; then
            sudo DEBIAN_FRONTEND=noninteractive apt install -y liblgpio-dev
        fi
        if apt-cache show python3-rpi-lgpio >/dev/null 2>&1; then
            sudo DEBIAN_FRONTEND=noninteractive apt install -y python3-rpi-lgpio
        fi
    fi
    log_success "Abhängigkeiten installiert"

    # ── Schritt 4: Repository klonen ──
    log_step "Schritt 4/8: Repository vorbereiten"
    if [ ! -d "/home/$OPENWB_USER/openwb-trixie" ]; then
        log "Klone Repository..."
        sudo mkdir -p "/home/$OPENWB_USER"
        cd "/home/$OPENWB_USER"
        git clone https://github.com/Xerolux/openwb-trixie.git
        cd openwb-trixie
        SCRIPT_DIR="$(pwd)"
    else
        log "Repository vorhanden"
        cd "/home/$OPENWB_USER/openwb-trixie"
        SCRIPT_DIR="$(pwd)"
    fi

    PATCHES_SRC_DIR="$SCRIPT_DIR"

    # ── Schritt 5: GPIO ──
    log_step "Schritt 5/8: GPIO-Konfiguration"
    configure_gpio

    # ── Schritt 6: PHP ──
    log_step "Schritt 6/8: PHP konfigurieren"
    configure_php

    # ── Schritt 7: Python ──
    case "$MODE" in
        venv)
            log_step "Schritt 7/8: Python venv erstellen"
            do_python_venv
            ;;
        python39)
            log_step "Schritt 7/8: Python 3.9.25 kompilieren"
            do_python_39
            ;;
        python314)
            log_step "Schritt 7/8: Python 3.14.4 kompilieren + venv"
            do_python_314
            ;;
    esac

    # ── Schritt 8: OpenWB ──
    log_step "Schritt 8/8: OpenWB installieren + patches"
    do_openwb_install
    do_runtime_patches
    do_post_update_hook

    # Bereits aktivierte Feature-Patches anwenden (ohne Menü)
    patches_apply_enabled

    # Services starten
    log "Starte Services..."
    sudo systemctl daemon-reload
    for svc in mosquitto mosquitto_local; do
        sudo systemctl enable "$svc" 2>/dev/null || true
        sudo systemctl restart "$svc" 2>/dev/null || true
    done
    sudo systemctl enable openwb2 2>/dev/null || true
    sudo systemctl restart openwb2 2>/dev/null || true
    sleep 3
    sudo systemctl restart openwb-simpleAPI 2>/dev/null || true

    # Finale Überprüfung
    do_final_check
}

main "$@"
