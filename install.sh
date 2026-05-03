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
#   ./install.sh --status         Status anzeigen
#   ./install.sh --diagnose       Diagnose-Archiv erstellen
#   ./install.sh --diagnose-upload Diagnose-Archiv erstellen + zu paste.blueml.eu hochladen
#   ./install.sh --dry-run        Nur anzeigen, nichts ändern
#   ./install.sh --help           Hilfe anzeigen
#
# Getestet auf: x86_64, ARM64, ARM32, Proxmox, Raspberry Pi
# ============================================================================

set -Ee -o pipefail

INSTALLER_VERSION="2026-05-01"
BUILD_ID="8daeea9"

# ============================================================================
# Argumente parsen
# ============================================================================
MODE="${MODE:-}"
NONINTERACTIVE="${NONINTERACTIVE:-0}"
DRY_RUN="${DRY_RUN:-0}"
DIAG_UPLOAD_CONSENT="${DIAG_UPLOAD_CONSENT:-0}"
PASTE_UPLOAD_URL="${PASTE_UPLOAD_URL:-https://paste.blueml.eu}"
_GH_BASE="https://raw.githubusercontent.com/Xerolux/openwb-trixie/main"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"
if [ ! -d "$LIB_DIR" ] || [ ! -f "$LIB_DIR/menu.sh" ]; then
    LIB_DIR="$(mktemp -d)/lib"
    mkdir -p "$LIB_DIR"
    for _lib in menu.sh diagnostics.sh preflight.sh bubbletea_menu.go go.mod; do
        curl -fsSL "${_GH_BASE}/lib/${_lib}" -o "${LIB_DIR}/${_lib}" 2>/dev/null || true
    done
fi

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
        --status|-s)
            MODE="status"
            shift
            ;;
        --diagnose|--diag|-d)
            MODE="diagnose"
            shift
            ;;
        --diagnose-upload|--diag-upload)
            MODE="diagnose_upload"
            shift
            ;;
        --non-interactive|-n)
            NONINTERACTIVE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            cat <<'EOF'
OpenWB Trixie Installer

Nutzung:
  ./install.sh [OPTION]

Optionen:
  --venv, -v             Installation mit System-Python + venv (empfohlen)
  --python39, --legacy   Installation mit Python 3.9.25 (Legacy)
  --python314, --latest  Installation mit Python 3.14.4 + venv
  --patches              Feature-Patches verwalten
  --status, -s           Systemstatus anzeigen
  --diagnose, -d         Diagnose-Archiv erzeugen
  --diagnose-upload      Diagnose-Archiv erzeugen und hochladen (mit Hinweis)
  --non-interactive, -n  Ohne Menü starten
  --dry-run              Aktionen nur anzeigen, nicht ausführen
  --help, -h             Diese Hilfe anzeigen
EOF
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
log_dryrun()  { echo -e "${YELLOW}[$(date +'%H:%M:%S')] DRYRUN${NC} $1"; }

run_cmd() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "$*"
        return 0
    fi
    "$@"
}

run_step() {
    local step_title="$1"
    shift
    local start_ts end_ts elapsed
    log_step "$step_title"
    start_ts=$(date +%s)
    "$@"
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    log_success "$step_title abgeschlossen in ${elapsed}s"
}

# Diagnose-Funktionen auslagern (Wartbarkeit)
if [ -f "$LIB_DIR/diagnostics.sh" ]; then
    # shellcheck disable=SC1090
    source "$LIB_DIR/diagnostics.sh"
fi
if [ -f "$LIB_DIR/preflight.sh" ]; then
    # shellcheck disable=SC1090
    source "$LIB_DIR/preflight.sh"
fi
if [ -f "$LIB_DIR/menu.sh" ]; then
    # shellcheck disable=SC1090
    source "$LIB_DIR/menu.sh"
fi

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
TOOL_DIR="/opt/openwb-tools"
TOOL_CONF="$TOOL_DIR/enabled.conf"
if _src_dir="$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" && _tgt="$(cd "$_src_dir" 2>/dev/null && pwd)"; then
    SCRIPT_DIR="$_tgt"
else
    SCRIPT_DIR="$HOME"
fi
REPO_DIR="/home/$OPENWB_USER/openwb-trixie"
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
    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -c 2>/dev/null | grep -q "trixie"
        return $?
    fi
    return 1
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
        "$VENV_DIR/bin/python3" -c 'import sys; v=sys.version_info; print(f"{v.major}.{v.minor}")' 2>/dev/null
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
    local user_groups
    if id "$OPENWB_USER" >/dev/null 2>&1; then
        log "Benutzer '$OPENWB_USER' existiert"
    else
        log "Erstelle Benutzer '$OPENWB_USER'..."
        sudo useradd -m -s /bin/bash "$OPENWB_USER"
    fi
    user_groups="$(id -nG "$OPENWB_USER" 2>/dev/null || true)"
    if ! printf '%s\n' "$user_groups" | grep -qw sudo; then
        sudo usermod -aG sudo "$OPENWB_USER"
    fi
    if ! printf '%s\n' "$user_groups" | grep -qw gpio; then
        sudo groupadd gpio 2>/dev/null || true
        sudo usermod -aG gpio "$OPENWB_USER" 2>/dev/null || true
    fi
    local sudoers_file="/etc/sudoers.d/openwb-nopasswd"
    if [ ! -f "$sudoers_file" ]; then
        echo "$OPENWB_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "$sudoers_file" >/dev/null
        sudo chmod 440 "$sudoers_file"
        log "NOPASSWD sudo für '$OPENWB_USER' eingerichtet"
    fi
    if [ "$(id -u)" = "0" ] && [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        log_warning "Kein Terminal - überspringe Passwort-Setzung für '$OPENWB_USER'"
    elif ! sudo passwd -S "$OPENWB_USER" 2>/dev/null | grep -q "P "; then
        echo ""
        log_warning "Bitte Passwort für Benutzer '$OPENWB_USER' vergeben:"
        sudo passwd "$OPENWB_USER" < /dev/tty
    fi
}

ensure_openwb_password_for_sudo() {
    if sudo -H -u "$OPENWB_USER" sudo -n true >/dev/null 2>&1; then
        log "Sudo für '$OPENWB_USER' funktioniert bereits ohne Passwortabfrage"
        return 0
    fi

    if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        log_error "Kein interaktives Terminal gefunden."
        log_error "Bitte setze manuell ein Passwort: sudo passwd $OPENWB_USER"
        exit 1
    fi

    echo ""
    log_warning "Bitte jetzt ein Passwort für den Benutzer '$OPENWB_USER' vergeben."
    log "Eingabe startet mit: sudo passwd $OPENWB_USER"
    sudo passwd "$OPENWB_USER" < /dev/tty
    log_success "Passwort für '$OPENWB_USER' wurde gesetzt"
}

run_as_openwb_user() {
    if [ "${OPENWB_RUN_AS_USER:-0}" = "1" ]; then
        return 0
    fi
    ensure_openwb_user

    if [ "$(id -u)" = "0" ]; then
        export OPENWB_RUN_AS_USER=1
        log "Installer läuft als root - überspringe Benutzerwechsel"
        return 0
    fi

    if [ "$(id -un)" = "$OPENWB_USER" ]; then
        export OPENWB_RUN_AS_USER=1
        return 0
    fi

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
    ensure_openwb_password_for_sudo
    log "Starte Installer als Benutzer '$OPENWB_USER'..."
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
Type=simple
ExecStart=/usr/sbin/mosquitto -c /etc/mosquitto/mosquitto_local.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable mosquitto_local >/dev/null 2>&1 || true
    sudo systemctl mask mosquitto_local-sysv 2>/dev/null || true
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
    local patch_req="$tmp_dir/patch_requirements.sh"
    trap 'rm -rf "$tmp_dir"' RETURN

    cat > "$patch_req" << 'PATCHEOF'
#!/bin/bash
REQ="${OPENWBBASEDIR:-/var/www/html/openWB}/requirements.txt"
[ -f "$REQ" ] || exit 0
sed -i -E '/^pymodbus==|^paho.mqtt==/!s/==[0-9][0-9.a-zA-Z+-]*[[:space:]]*$//' "$REQ"
PATCHEOF
    chmod +x "$patch_req"

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
            -e "s@sudo -u \"\\\$OPENWB_USER\" pip install -r \"\\\${OPENWBBASEDIR}/requirements.txt\"@bash ${tmp_dir}/patch_requirements.sh; /opt/openwb-venv/bin/pip3 install -U pip setuptools wheel; /opt/openwb-venv/bin/pip3 install -r \"\\\${OPENWBBASEDIR}/requirements.txt\"@g" \
            -e 's@^/usr/sbin/groupadd "\$OPENWB_GROUP"$@/usr/sbin/groupadd "$OPENWB_GROUP" || true@g' \
            -e 's@^/usr/sbin/useradd "\$OPENWB_USER" -g "\$OPENWB_GROUP" --create-home$@/usr/sbin/useradd "$OPENWB_USER" -g "$OPENWB_GROUP" --create-home || true@g' \
            -e 's@^ln -s "\${OPENWBBASEDIR}/data/config/openwb2.service"@ln -sfn "${OPENWBBASEDIR}/data/config/openwb2.service"@g' \
            -e 's@^ln -s "\${OPENWBBASEDIR}/data/config/openwb-simpleAPI.service"@ln -sfn "${OPENWBBASEDIR}/data/config/openwb-simpleAPI.service"@g' \
            "$install_script"

        sed -E -i \
            -e "s@(^[[:space:]]*sudo -u \"\\\$OPENWB_USER\"[[:space:]]+)pip([[:space:]]+install[[:space:]]+-r[[:space:]]+)@bash ${tmp_dir}/patch_requirements.sh; /opt/openwb-venv/bin/pip3\\2@g" \
            -e "s@(^[[:space:]]*)pip([[:space:]]+install[[:space:]]+-r[[:space:]]+)@bash ${tmp_dir}/patch_requirements.sh; /opt/openwb-venv/bin/pip3\\2@g" \
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
    sed -i 's/^systemctl start openwb2/echo "openwb2 start deferred (trixie patching)"/g' "$install_script"
    sed -i '/sudo reboot/d' "$install_script"

    log "Führe OpenWB Installer aus..."
    sudo DEBIAN_FRONTEND=noninteractive bash "$install_script" || true
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

        # requirements.txt für Python 3.13 patchen (Pins entfernen, pymodbus+paho_mqtt behalten)
        local req="$OPENWB_DIR/requirements.txt"
        if [ -f "$req" ]; then
            log "Patche requirements.txt (Pins entfernen, pymodbus+paho_mqtt behalten)..."
            sudo sed -i -E '/^pymodbus==|^paho.mqtt==/!s/==[0-9][0-9.a-zA-Z+-]*[[:space:]]*$//' "$req"
        fi
    fi

    # mosquitto_local systemd Unit (für beide Modi)
    ensure_mosquitto_local_unit

    sudo systemctl daemon-reload
    log_success "Runtime Patches angewendet"
}

install_boot_service() {
    local boot_script="$SCRIPT_DIR/openwb-trixie-boot.sh"
    if [ ! -f "$boot_script" ]; then
        log_warning "Boot-Service Skript nicht gefunden: $boot_script"
        return 0
    fi

    sudo cp "$boot_script" /opt/openwb-trixie-boot.sh
    sudo chmod 755 /opt/openwb-trixie-boot.sh

    sudo tee /etc/systemd/system/openwb-trixie-boot.service > /dev/null <<'EOF'
[Unit]
Description=OpenWB Trixie Boot Patches
Before=openwb2.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/openwb-trixie-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable openwb-trixie-boot.service >/dev/null 2>&1
    log_success "Boot-Service installiert (läuft vor openwb2 bei jedem Start)"
}

ensure_pip3_wrapper() {
    if [ "$MODE" != "venv" ] && [ "$MODE" != "python314" ]; then
        return 0
    fi

    local wrapper="/usr/local/bin/pip3"
    if [ -f "$wrapper" ] && head -1 "$wrapper" | grep -q openwb-venv; then
        return 0
    fi

    log "Erstelle pip3-Wrapper -> venv..."
    sudo tee "$wrapper" > /dev/null <<'WRAPPER'
#!/bin/bash
if [ -x /opt/openwb-venv/bin/pip3 ]; then
    exec /opt/openwb-venv/bin/pip3 "$@"
else
    exec /usr/bin/pip3 "$@"
fi
WRAPPER
    sudo chmod 755 "$wrapper"
    log_success "pip3-Wrapper installiert"

    sudo mkdir -p /opt/openwb-venv/bin
    sudo tee /opt/openwb-venv/bin/pip3-system > /dev/null <<'SYSPIP'
#!/bin/bash
exec /usr/bin/pip3 "$@"
SYSPIP
    sudo chmod 755 /opt/openwb-venv/bin/pip3-system
}

fix_openwb_homedir() {
    if [ -d "/home/$OPENWB_USER" ]; then
        sudo chown -R "$OPENWB_USER:$OPENWB_USER" "/home/$OPENWB_USER"
    fi
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

patch_matches_arch() {
    local file="$1"
    local arch
    arch=$(patch_get_field "$file" "Arch")
    [ -z "$arch" ] && return 0

    case "$arch" in
        arm)  is_arm_arch ;;
        rpi)  is_arm_arch && is_raspberry_pi ;;
        x86)  ! is_arm_arch ;;
        *)    return 0 ;;
    esac
}

patches_load_enabled() {
    if [ ! -d "$PATCH_DIR" ]; then
        sudo mkdir -p "$PATCH_DIR"
        sudo chown "$(id -un):$(id -un)" "$PATCH_DIR" 2>/dev/null || true
    fi
    [ -f "$PATCH_CONF" ] || sudo touch "$PATCH_CONF"
    sudo chown "$(id -un):$(id -un)" "$PATCH_CONF" 2>/dev/null || true
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

whiptail_patches_menu() {
    if [ ! -d "$PATCHES_SRC_DIR/patches" ]; then
        whiptail --title "Fehler" --msgbox "patches/ Verzeichnis nicht gefunden.\nBitte Repository aktualisieren." 10 50
        return 1
    fi

    patches_load_enabled

    local args=()
    local patch_files=()

    while IFS= read -r pfile; do
        [ -z "$pfile" ] && continue
        local full="$PATCHES_SRC_DIR/patches/$pfile"
        patch_matches_arch "$full" || continue
        local pid name desc
        pid=$(patch_get_field "$full" "Id")
        name=$(patch_get_field "$full" "Name")
        desc=$(patch_get_field "$full" "Desc")
        [ -z "$pid" ] && continue

        patch_files+=("$pid")
        if patch_is_enabled "$pid"; then
            args+=("$pid" "$name — $desc" "ON")
        else
            args+=("$pid" "$name — $desc" "OFF")
        fi
    done <<< "$(patches_discover "$PATCHES_SRC_DIR/patches")"

    if [ ${#args[@]} -eq 0 ]; then
        whiptail --title "Feature-Patches" --msgbox "Keine Patches verfügbar." 10 50
        return 0
    fi

    local selected
    selected=$(whiptail --title "Feature-Patches" \
        --cancel-button "Zurück" \
        --checklist "\n[*] = installiert    [ ] = verfügbar\n\nPatches werden nach OpenWB-Updates automatisch reapplied." \
        22 78 ${#patch_files[@]} \
        "${args[@]}" \
        3>&1 1>&2 2>&3)

    local rc=$?
    [ $rc -ne 0 ] && return 0

    # selected enthält IDs in Anführungszeichen, z.B.: "force-secondary-update" "no-reboot-on-update"
    local sel_pids=()
    eval 'for w in '$selected'; do sel_pids+=("$w"); done'

    # Patches die aktiviert waren aber nicht mehr ausgewählt sind → entfernen
    for pid in "${patch_files[@]}"; do
        local is_sel=false
        for sp in "${sel_pids[@]}"; do
            [ "$pid" = "$sp" ] && is_sel=true && break
        done

        local pfile=""
        for f in "$PATCHES_SRC_DIR"/patches/*.sh; do
            [ -f "$f" ] || continue
            if [ "$(patch_get_field "$f" "Id")" = "$pid" ]; then
                pfile="$f"
                break
            fi
        done
        [ -z "$pfile" ] && continue

        export OPENWB_DIR VENV_DIR
        source "$pfile"

        if [ "$is_sel" = true ] && ! patch_is_enabled "$pid"; then
            # Installieren
            if patch_apply; then
                patch_enable "$pid"
            fi
        elif [ "$is_sel" = false ] && patch_is_enabled "$pid"; then
            # Entfernen
            if patch_revert; then
                patch_disable "$pid"
            fi
        fi
    done

    whiptail --title "Fertig" --msgbox "Patch-Änderungen angewendet.\nAktivierte Patches werden nach OpenWB-Updates automatisch reapplied." 10 60
}

patches_menu() {
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
            patch_matches_arch "$full" || continue
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
        echo -e "  ${BB}│${W}  ${DIM}[0] Zurück zum Hauptmenü${W}                                ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${DIM}[r] Patch entfernen${W}                                   ${BB}│${W}"
        echo -e "  ${BB}└──────────────────────────────────────────────────────────┘${W}"
        echo ""

        echo -ne "  ${BOLD}Wahl${W} [0-${count}/r]: "
        read -n 1 -r < /dev/tty
        echo

        case "$REPLY" in
            0|"") return 0 ;;
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
# Legacy Wallbox Module (eigener Menüpunkt)
# ============================================================================

legacy_wallbox_ids() {
    echo "legacy-wallbox-goe legacy-wallbox-keba legacy-wallbox-simpleevse"
}

whiptail_legacy_wallbox_menu() {
    if [ ! -d "$PATCHES_SRC_DIR/patches" ]; then
        whiptail --title "Fehler" --msgbox "patches/ Verzeichnis nicht gefunden." 10 50
        return 1
    fi

    patches_load_enabled

    local args=()
    local patch_files=()

    local wb_id
    for wb_id in $(legacy_wallbox_ids); do
        local pfile=""
        for f in "$PATCHES_SRC_DIR"/patches/*.sh; do
            [ -f "$f" ] || continue
            if [ "$(patch_get_field "$f" "Id")" = "$wb_id" ]; then
                pfile="$f"
                break
            fi
        done
        [ -z "$pfile" ] && continue
        if ! patch_matches_arch "$pfile"; then
            continue
        fi

        local name desc
        name=$(patch_get_field "$pfile" "Name")
        desc=$(patch_get_field "$pfile" "Desc")

        patch_files+=("$wb_id")
        if patch_is_enabled "$wb_id"; then
            args+=("$wb_id" "$name — $desc" "ON")
        else
            args+=("$wb_id" "$name — $desc" "OFF")
        fi
    done

    if [ ${#args[@]} -eq 0 ]; then
        whiptail --title "Legacy Wallbox Module" --msgbox "Keine Legacy-Wallbox-Module gefunden.\nBitte Repository aktualisieren." 10 55
        return 0
    fi

    local selected
    selected=$(whiptail --title "Legacy Wallbox Module" \
        --cancel-button "Zurück" \
        --checklist "\n[*] = installiert    [ ] = verfügbar\n\nLegacy Wallbox-Module fuer openWB 2.x.\nDiese Module wurden aus evcc-Code abgeleitet und\nfuer openWB 2.x angepasst. Sie werden nach\nOpenWB-Updates automatisch reinstalliert.\n\nHINWEIS: Nicht auf echter Hardware getestet!" \
        20 78 ${#patch_files[@]} \
        "${args[@]}" \
        3>&1 1>&2 2>&3)

    local rc=$?
    [ $rc -ne 0 ] && return 0

    local sel_pids=()
    eval 'for w in '$selected'; do sel_pids+=("$w"); done'

    for wb_id in "${patch_files[@]}"; do
        local is_sel=false
        for sp in "${sel_pids[@]}"; do
            [ "$wb_id" = "$sp" ] && is_sel=true && break
        done

        local pfile=""
        for f in "$PATCHES_SRC_DIR"/patches/*.sh; do
            [ -f "$f" ] || continue
            if [ "$(patch_get_field "$f" "Id")" = "$wb_id" ]; then
                pfile="$f"
                break
            fi
        done
        [ -z "$pfile" ] && continue

        export OPENWB_DIR VENV_DIR PATCHES_SRC_DIR REPO_DIR
        source "$pfile"

        if [ "$is_sel" = true ] && ! patch_is_enabled "$wb_id"; then
            if patch_apply; then
                patch_enable "$wb_id"
            fi
        elif [ "$is_sel" = false ] && patch_is_enabled "$wb_id"; then
            if patch_revert; then
                patch_disable "$wb_id"
            fi
        fi
    done

    whiptail --title "Fertig" --msgbox "Legacy Wallbox-Änderungen angewendet.\nAktivierte Module werden nach OpenWB-Updates\nautomatisch reinstalliert.\n\nopenWB neu starten: sudo systemctl restart openwb2" 12 55
}

legacy_wallbox_menu() {
    if [ ! -d "$PATCHES_SRC_DIR/patches" ]; then
        log_error "patches/ Verzeichnis nicht gefunden"
        return 1
    fi

    patches_load_enabled

    local BOLD='\033[1m' DIM='\033[2m' W='\033[0m'
    local GR='\033[0;32m' BG='\033[1;32m' BB='\033[1;34m'
    local BY='\033[1;33m' RED='\033[0;31m' CY='\033[0;36m'

    while true; do
        local count=0
        local wb_ids=()

        echo ""
        echo -e "  ${BB}┌──────────────────────────────────────────────────────────┐${W}"
        echo -e "  ${BB}│${W}        ${BOLD}Legacy Wallbox Module (evcc-optimiert)${W}              ${BB}│${W}"
        echo -e "  ${BB}├──────────────────────────────────────────────────────────┤${W}"
        echo -e "  ${BB}│${W}  ${DIM}Module fuer openWB 2.x, nicht auf Hardware getestet${W}      ${BB}│${W}"
        echo -e "  ${BB}├──────────────────────────────────────────────────────────┤${W}"

        local wb_id
        for wb_id in $(legacy_wallbox_ids); do
            local pfile=""
            for f in "$PATCHES_SRC_DIR"/patches/*.sh; do
                [ -f "$f" ] || continue
                if [ "$(patch_get_field "$f" "Id")" = "$wb_id" ]; then
                    pfile="$f"
                    break
                fi
            done
            [ -z "$pfile" ] && continue
            if ! patch_matches_arch "$pfile"; then
                continue
            fi

            local name desc
            name=$(patch_get_field "$pfile" "Name")
            desc=$(patch_get_field "$pfile" "Desc")

            count=$((count + 1))
            wb_ids+=("$wb_id")

            if patch_is_enabled "$wb_id"; then
                echo -e "  ${BB}│${W}  ${GR}[${count}] INSTALLED${W}  ${BOLD}${name}${W}"
            else
                echo -e "  ${BB}│${W}  ${BY}[${count}] verfügbar${W}   ${name}${W}"
            fi
            echo -e "  ${BB}│${W}       ${DIM}${desc}${W}"
        done

        echo -e "  ${BB}│${W}                                                          ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${DIM}[0] Zurück zum Hauptmenü${W}                                ${BB}│${W}"
        echo -e "  ${BB}│${W}  ${DIM}[r] Modul entfernen${W}                                   ${BB}│${W}"
        echo -e "  ${BB}└──────────────────────────────────────────────────────────┘${W}"
        echo ""

        echo -ne "  ${BOLD}Wahl${W} [0-${count}/r]: "
        read -n 1 -r < /dev/tty
        echo

        case "$REPLY" in
            0|"") return 0 ;;
            r|R)
                echo -ne "  Modul-Nummer zum ${RED}Entfernen${W}: "
                read -r num < /dev/tty
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$count" ]; then
                    local pid="${wb_ids[$((num-1))]}"
                    local pfile=""
                    for f in "$PATCHES_SRC_DIR"/patches/*.sh; do
                        [ -f "$f" ] || continue
                        if [ "$(patch_get_field "$f" "Id")" = "$pid" ]; then
                            pfile="$f"
                            break
                        fi
                    done
                    [ -z "$pfile" ] && continue
                    export OPENWB_DIR VENV_DIR PATCHES_SRC_DIR REPO_DIR
                    source "$pfile"
                    if patch_revert; then
                        patch_disable "$pid"
                        log_success "Modul '$pid' entfernt und deaktiviert"
                    else
                        log_error "Modul '$pid' konnte nicht entfernt werden"
                    fi
                else
                    echo -e "  ${RED}Ungültige Nummer${W}"
                fi
                continue
                ;;
        esac

        if [[ "$REPLY" =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$count" ]; then
            local pid="${wb_ids[$((REPLY-1))]}"
            local pfile=""
            for f in "$PATCHES_SRC_DIR"/patches/*.sh; do
                [ -f "$f" ] || continue
                if [ "$(patch_get_field "$f" "Id")" = "$pid" ]; then
                    pfile="$f"
                    break
                fi
            done
            [ -z "$pfile" ] && continue
            export OPENWB_DIR VENV_DIR PATCHES_SRC_DIR REPO_DIR
            source "$pfile"

            if patch_is_enabled "$pid"; then
                echo -e "  ${GR}Modul '$pid' ist bereits installiert.${W}"
                echo -ne "  Entfernen? (j/N): "
                read -n 1 -r yn < /dev/tty
                echo
                if [[ "$yn" =~ ^[JjYy]$ ]]; then
                    if patch_revert; then
                        patch_disable "$pid"
                        log_success "Modul '$pid' entfernt und deaktiviert"
                    fi
                fi
            else
                echo -e "  Installiere '${BOLD}$(patch_get_field "$pfile" "Name")${W}'..."
                if patch_apply; then
                    patch_enable "$pid"
                    log_success "Modul '$pid' installiert und aktiviert"
                else
                    log_error "Modul '$pid' konnte nicht installiert werden"
                fi
            fi
        fi
    done
}

# ============================================================================
# Tools (modular, installierbar/entfernbar)
# ============================================================================
TOOLS_SRC_DIR=""

tools_discover() {
    local tdir="$1"
    local tools=()
    for f in "$tdir"/*.sh; do
        [ -f "$f" ] || continue
        tools+=("$(basename "$f")")
    done
    printf '%s\n' "${tools[@]}" | sort
}

tool_get_field() {
    local file="$1" field="$2"
    grep -m1 "^# $field:" "$file" 2>/dev/null | sed "s/^# $field: *//"
}

tools_load_enabled() {
    if [ ! -d "$TOOL_DIR" ]; then
        sudo mkdir -p "$TOOL_DIR"
        sudo chown "$OPENWB_USER:$OPENWB_USER" "$TOOL_DIR" 2>/dev/null || true
    fi
    [ -f "$TOOL_CONF" ] || sudo touch "$TOOL_CONF"
    sudo chown "$OPENWB_USER:$OPENWB_USER" "$TOOL_CONF" 2>/dev/null || true
}

tool_is_enabled() {
    local tid="$1"
    grep -qx "$tid" "$TOOL_CONF" 2>/dev/null
}

tool_enable() {
    local tid="$1"
    tools_load_enabled
    if ! tool_is_enabled "$tid"; then
        echo "$tid" >> "$TOOL_CONF"
    fi
}

tool_disable() {
    local tid="$1"
    [ -f "$TOOL_CONF" ] || return
    sed -i "/^${tid}$/d" "$TOOL_CONF"
}

whiptail_tools_menu() {
    if [ ! -d "$TOOLS_SRC_DIR/tools" ]; then
        whiptail --title "Fehler" --msgbox "tools/ Verzeichnis nicht gefunden." 10 50
        return 1
    fi

    tools_load_enabled

    local args=()
    local tool_files=()

    while IFS= read -r tfile; do
        [ -z "$tfile" ] && continue
        local full="$TOOLS_SRC_DIR/tools/$tfile"
        local tid name desc
        tid=$(tool_get_field "$full" "Id")
        name=$(tool_get_field "$full" "Name")
        desc=$(tool_get_field "$full" "Desc")
        [ -z "$tid" ] && continue

        tool_files+=("$tid")
        if tool_is_enabled "$tid"; then
            args+=("$tid" "$name — $desc" "ON")
        else
            args+=("$tid" "$name — $desc" "OFF")
        fi
    done <<< "$(tools_discover "$TOOLS_SRC_DIR/tools")"

    if [ ${#args[@]} -eq 0 ]; then
        whiptail --title "Tools" --msgbox "Keine Tools verfügbar." 10 50
        return 0
    fi

    local selected
    selected=$(whiptail --title "Tools" \
        --cancel-button "Zurück" \
        --checklist "\n[*] = installiert    [ ] = verfügbar\n\nLeertaste = Auswählen, Enter = Übernehmen" \
        22 78 ${#tool_files[@]} \
        "${args[@]}" \
        3>&1 1>&2 2>&3)

    local rc=$?
    [ $rc -ne 0 ] && return 0

    local sel_tids=()
    eval 'for w in '$selected'; do sel_tids+=("$w"); done'

    for tid in "${tool_files[@]}"; do
        local is_sel=false
        for st in "${sel_tids[@]}"; do
            [ "$tid" = "$st" ] && is_sel=true && break
        done

        local tfile=""
        for f in "$TOOLS_SRC_DIR"/tools/*.sh; do
            [ -f "$f" ] || continue
            if [ "$(tool_get_field "$f" "Id")" = "$tid" ]; then
                tfile="$f"
                break
            fi
        done
        [ -z "$tfile" ] && continue

        export OPENWB_DIR VENV_DIR
        source "$tfile"

        if [ "$is_sel" = true ] && ! tool_is_enabled "$tid"; then
            if tool_apply; then
                tool_enable "$tid"
            fi
        elif [ "$is_sel" = false ] && tool_is_enabled "$tid"; then
            if tool_revert; then
                tool_disable "$tid"
            fi
        fi
    done

    whiptail --title "Fertig" --msgbox "Tool-Änderungen angewendet." 8 40
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
do_patches_mode() {
    if [ ! -d "$OPENWB_DIR" ]; then
        log_error "OpenWB ist noch nicht installiert! Bitte zuerst Option 1, 2 oder 3 ausführen."
        return 1
    fi

    sudo mkdir -p "$PATCH_DIR"
    sudo chown "$OPENWB_USER:$OPENWB_USER" "$PATCH_DIR" 2>/dev/null || true
    sudo touch "$PATCH_CONF" 2>/dev/null || true
    sudo chown "$OPENWB_USER:$OPENWB_USER" "$PATCH_CONF" 2>/dev/null || true

    run_as_openwb_user

    if [ -d "/home/$OPENWB_USER/openwb-trixie" ]; then
        cd "/home/$OPENWB_USER/openwb-trixie"
        log "Aktualisiere Repository..."
        git pull --ff-only 2>/dev/null || git reset --hard origin/main 2>/dev/null || true
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

    if [ ! -d "$PATCHES_SRC_DIR/patches" ]; then
        log_error "patches/ Verzeichnis nicht gefunden in $PATCHES_SRC_DIR"
        return 1
    fi

    patches_apply_enabled
    patches_menu
    echo ""
}

ensure_repo() {
    if [ -d "$SCRIPT_DIR/patches" ] && [ -d "$SCRIPT_DIR/tools" ]; then
        REPO_DIR="$SCRIPT_DIR"
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        log "Installiere git..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git 2>/dev/null || true
    fi

    if [ -d "$REPO_DIR" ]; then
        cd "$REPO_DIR"
        git pull --ff-only 2>/dev/null || git reset --hard origin/main 2>/dev/null || true
        if [ -f "$REPO_DIR/requirements.txt" ]; then
            return 0
        fi
        log_warning "Repository vorhanden aber unvollständig, klone neu..."
        cd /tmp
        sudo rm -rf "$REPO_DIR"
    fi

    log "Bereite Repository vor..."
    sudo mkdir -p "$REPO_DIR"
    sudo chown "$(id -un):$(id -gn)" "$REPO_DIR" 2>/dev/null || true
    if ! git clone https://github.com/Xerolux/openwb-trixie.git "$REPO_DIR"; then
        log_error "git clone fehlgeschlagen - prüfe Netzwerkverbindung"
        sudo rm -rf "$REPO_DIR"
        exit 1
    fi
}

verify_repo() {
    if [ ! -d "$REPO_DIR/.git" ] || [ ! -f "$REPO_DIR/requirements.txt" ]; then
        log_error "Repository nicht gefunden oder unvollständig: $REPO_DIR"
        log_error "Bitte erneut starten oder manuell klonen:"
        log_error "  git clone https://github.com/Xerolux/openwb-trixie.git $REPO_DIR"
        exit 1
    fi
}

show_status() {
    local BOLD='\033[1m' DIM='\033[2m' W='\033[0m'
    local GR='\033[0;32m' BG='\033[1;32m' BB='\033[1;34m'
    local BY='\033[1;33m' RED='\033[0;31m' CY='\033[0;36m'

    echo ""
    echo -e "  ${BB}┌─────────────────────────────────────────────────────────────┐${W}"
    echo -e "  ${BB}│${W}           ${BG}OpenWB Trixie — System Status${W}                  ${BB}│${W}"
    echo -e "  ${BB}├─────────────────────────────────────────────────────────────┤${W}"

    local deb_ver
    deb_ver=$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-${VERSION:-?}}" || echo "?")
    echo -e "  ${BB}│${W}  ${BOLD}Debian:${W}       $deb_ver"
    echo -e "  ${BB}│${W}  ${BOLD}Architektur:${W}  $(uname -m)$(is_raspberry_pi && echo " (Raspberry Pi)" || true)"

    local ip_addr
    ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo -e "  ${BB}│${W}  ${BOLD}IP:${W}           ${CY}${ip_addr:-?}${W}"
    echo -e "  ${BB}│${W}  ${BOLD}Hostname:${W}     $(hostname 2>/dev/null || echo "?")"

    echo -e "  ${BB}├─────────────────────────────────────────────────────────────┤${W}"
    echo -e "  ${BB}│${W}  ${BOLD}Python / venv:${W}"

    if [ -d "$VENV_DIR" ]; then
        echo -e "  ${BB}│${W}    ${GR}venv:${W}     ${BG}$($VENV_DIR/bin/python3 --version 2>&1 | awk '{print $2}')${W} ($VENV_DIR)"
        echo -e "  ${BB}│${W}    ${GR}System:${W}   $(python3 --version 2>&1 | awk '{print $2}')"
    else
        echo -e "  ${BB}│${W}    ${RED}venv nicht gefunden${W}"
    fi

    echo -e "  ${BB}├─────────────────────────────────────────────────────────────┤${W}"
    echo -e "  ${BB}│${W}  ${BOLD}Installer:${W}"

    local current_build
    if [ -d "$REPO_DIR/.git" ]; then
        current_build=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
    elif [ -d "$SCRIPT_DIR/.git" ]; then
        current_build=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
    else
        current_build="${BUILD_ID:-?}"
    fi

    local remote_build
    remote_build=$(git ls-remote --refs https://github.com/Xerolux/openwb-trixie.git HEAD 2>/dev/null | awk '{print substr($1,1,7)}' || true)

    echo -e "  ${BB}│${W}    ${BOLD}Installiert:${W}  ${BG}${current_build}${W}"
    if [ -n "$remote_build" ]; then
        if [ "$current_build" = "$remote_build" ]; then
            echo -e "  ${BB}│${W}    ${BOLD}Aktuell:${W}      ${GR}${remote_build} (up to date)${W}"
        else
            echo -e "  ${BB}│${W}    ${BOLD}Aktuell:${W}      ${BY}${remote_build} (Update verfügbar!)${W}"
        fi
    fi

    echo -e "  ${BB}├─────────────────────────────────────────────────────────────┤${W}"
    echo -e "  ${BB}│${W}  ${BOLD}OpenWB:${W}"

    if [ -d "$OPENWB_DIR" ]; then
        local owb_ver
        owb_ver=$(cd "$OPENWB_DIR" 2>/dev/null && git log -1 --format='%h %cs' 2>/dev/null || echo "?")
        echo -e "  ${BB}│${W}    ${BOLD}Version:${W}     $owb_ver"
    else
        echo -e "  ${BB}│${W}    ${RED}nicht installiert${W}"
    fi

    echo -e "  ${BB}├─────────────────────────────────────────────────────────────┤${W}"
    echo -e "  ${BB}│${W}  ${BOLD}Services:${W}"

    for svc in mosquitto mosquitto_local openwb2 openwb-simpleAPI apache2 openwbRemoteSupport; do
        local status
        status=$(systemctl is-active "$svc" 2>/dev/null || echo "?")
        if [ "$status" = "active" ]; then
            echo -e "  ${BB}│${W}    ${GR}OK${W}    $svc"
        else
            echo -e "  ${BB}│${W}    ${RED}$status${W}  $svc"
        fi
    done

    if [ -f "$PATCH_CONF" ] && [ -s "$PATCH_CONF" ]; then
        echo -e "  ${BB}├─────────────────────────────────────────────────────────────┤${W}"
        echo -e "  ${BB}│${W}  ${BOLD}Feature-Patches:${W}"
        while IFS= read -r pid; do
            [ -z "$pid" ] && continue
            echo -e "  ${BB}│${W}    ${GR}aktiv${W}  $pid"
        done < "$PATCH_CONF"
    fi

    echo -e "  ${BB}├─────────────────────────────────────────────────────────────┤${W}"
    echo -e "  ${BB}│${W}  ${BOLD}Boot-Service:${W}  $(systemctl is-active openwb-trixie-boot.service 2>/dev/null || echo "?")"

    local pip3_status="fehlt"
    [ -f /usr/local/bin/pip3 ] && head -1 /usr/local/bin/pip3 2>/dev/null | grep -q openwb-venv && pip3_status="aktiv"
    echo -e "  ${BB}│${W}  ${BOLD}pip3-Wrapper:${W}  ${pip3_status}"

    local post_update_status="fehlt"
    [ -f "$OPENWB_DIR/data/config/post-update.sh" ] && post_update_status="installiert"
    echo -e "  ${BB}│${W}  ${BOLD}Post-Update:${W}   ${post_update_status}"
    if [ -f /tmp/openwb-trixie-last-diagnose-link.txt ]; then
        echo -e "  ${BB}│${W}  ${BOLD}Letzter Diagnose-Link:${W} $(cat /tmp/openwb-trixie-last-diagnose-link.txt 2>/dev/null)"
    fi

    echo -e "  ${BB}│${W}"
    echo -e "  ${BB}│${W}  ${CY}Web-Interface:${W}  http://${ip_addr:-?}"
    echo -e "  ${BB}└─────────────────────────────────────────────────────────────┘${W}"
    echo ""
}

main() {
    if [ "$MODE" = "status" ]; then
        show_status
        exit 0
    fi

    if [ "$MODE" = "diagnose" ]; then
        generate_diagnostics_bundle
        exit 0
    fi
    if [ "$MODE" = "diagnose_upload" ]; then
        local diag_file anon_file
        diag_file="$(generate_diagnostics_bundle | tail -n1)"
        anon_file="$(anonymize_diagnostics_bundle "$diag_file" | tail -n1)"
        upload_diagnostics_bundle "$anon_file"
        exit 0
    fi

    if ! is_trixie; then
        log_error "Dies ist KEIN Debian Trixie System!"
        log_error "Bitte zuerst Debian Trixie installieren."
        echo ""
        echo "Download: https://www.debian.org/devel/"
        exit 1
    fi

    local USE_WHIPTAIL=1
    if ensure_whiptail; then
        USE_WHIPTAIL=0
    fi

    log_success "Debian Trixie erkannt ($(cat /etc/debian_version 2>/dev/null || echo "?"))"
    log "Architektur: $(uname -m)$(is_raspberry_pi && echo ' (Raspberry Pi)' || true)"

    # Repository bereitstellen (fuer Patches + Tools)
    ensure_repo

    while [ -z "$MODE" ]; do
        local choice=""
        if command -v go >/dev/null 2>&1; then
            choice=$(bubbletea_main_menu)
        elif ensure_bubbletea_menu_tool; then
            choice=$(gum_main_menu)
        elif [ $USE_WHIPTAIL -eq 0 ]; then
            choice=$(whiptail_main_menu)
        else
            choice=$(text_main_menu)
        fi

        case "$choice" in
            quit) echo "Tschüss!"; exit 0 ;;
            venv|python39|python314) MODE="$choice" ;;
            patches)
                if [ ! -d "$OPENWB_DIR" ]; then
                    if [ $USE_WHIPTAIL -eq 0 ]; then
                        whiptail --title "Fehler" --msgbox "OpenWB ist noch nicht installiert!\nBitte zuerst Option 1, 2 oder 3 ausführen." 10 55
                    else
                        log_error "OpenWB ist noch nicht installiert!"
                    fi
                    continue
                fi

                sudo mkdir -p "$PATCH_DIR"
                sudo chown "$OPENWB_USER:$OPENWB_USER" "$PATCH_DIR" 2>/dev/null || true
                sudo touch "$PATCH_CONF" 2>/dev/null || true
                sudo chown "$OPENWB_USER:$OPENWB_USER" "$PATCH_CONF" 2>/dev/null || true

                run_as_openwb_user

                PATCHES_SRC_DIR="$REPO_DIR"
                patches_apply_enabled
                if [ $USE_WHIPTAIL -eq 0 ]; then
                    whiptail_patches_menu
                else
                    patches_menu
                fi
                continue
                ;;
            tools)
                if [ ! -d "$OPENWB_DIR" ]; then
                    if [ $USE_WHIPTAIL -eq 0 ]; then
                        whiptail --title "Fehler" --msgbox "OpenWB ist noch nicht installiert!\nBitte zuerst Option 1, 2 oder 3 ausführen." 10 55
                    else
                        log_error "OpenWB ist noch nicht installiert!"
                    fi
                    continue
                fi

                run_as_openwb_user
                TOOLS_SRC_DIR="$REPO_DIR"
                whiptail_tools_menu
                continue
                ;;
            legacy_wallbox)
                if [ ! -d "$OPENWB_DIR" ]; then
                    if [ $USE_WHIPTAIL -eq 0 ]; then
                        whiptail --title "Fehler" --msgbox "OpenWB ist noch nicht installiert!\nBitte zuerst Option 1, 2 oder 3 ausführen." 10 55
                    else
                        log_error "OpenWB ist noch nicht installiert!"
                    fi
                    continue
                fi

                run_as_openwb_user
                PATCHES_SRC_DIR="$REPO_DIR"
                if [ $USE_WHIPTAIL -eq 0 ]; then
                    whiptail_legacy_wallbox_menu
                else
                    legacy_wallbox_menu
                fi
                continue
                ;;
            status)
                show_status
                if [ $USE_WHIPTAIL -ne 0 ]; then
                    echo ""
                    read -p "  Enter drücken um fortzufahren..." -r < /dev/tty
                fi
                continue
                ;;
            diagnose)
                generate_diagnostics_bundle
                if [ $USE_WHIPTAIL -ne 0 ]; then
                    echo ""
                    read -p "  Enter drücken um fortzufahren..." -r < /dev/tty
                fi
                continue
                ;;
            diagnose_upload)
                local diag_file anon_file
                diag_file="$(generate_diagnostics_bundle | tail -n1)"
                anon_file="$(anonymize_diagnostics_bundle "$diag_file" | tail -n1)"
                upload_diagnostics_bundle "$anon_file"
                if [ $USE_WHIPTAIL -ne 0 ]; then
                    echo ""
                    read -p "  Enter drücken um fortzufahren..." -r < /dev/tty
                fi
                continue
                ;;
        esac
    done

    if [ "$MODE" = "patches" ]; then
        do_patches_mode
        exit 0
    fi

    # Als openwb-User ausführen
    run_as_openwb_user
    run_preflight_checks

    # ── Schritt 1: System aktualisieren ──
    run_step "Schritt 1/8: System aktualisieren" true
    recover_dpkg_if_needed
    run_cmd sudo apt update
    run_cmd sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

    # ── Schritt 2: Deutsche Standards ──
    run_step "Schritt 2/8: Deutsche Standards" configure_german_defaults

    # ── Schritt 3: Build-Abhängigkeiten ──
    run_step "Schritt 3/8: Abhängigkeiten installieren" true
    recover_dpkg_if_needed
    run_cmd sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        swig build-essential python3-dev python3-pip python3-venv \
        pkg-config libffi-dev libxml2-dev libxslt1-dev zlib1g-dev \
        git curl wget usbutils inotify-tools \
        apache2 libapache2-mod-php php php-gd php-curl php-xml php-json \
        mosquitto mosquitto-clients openssh-server

    if is_arm_arch && is_raspberry_pi; then
        run_cmd sudo DEBIAN_FRONTEND=noninteractive apt install -y dnsmasq 2>/dev/null || true
    fi

    if is_arm_arch && is_raspberry_pi; then
        run_cmd sudo DEBIAN_FRONTEND=noninteractive apt install -y libgpiod-dev 2>/dev/null || true
        if apt-cache show liblgpio-dev >/dev/null 2>&1; then
            run_cmd sudo DEBIAN_FRONTEND=noninteractive apt install -y liblgpio-dev
        fi
        if apt-cache show python3-rpi-lgpio >/dev/null 2>&1; then
            run_cmd sudo DEBIAN_FRONTEND=noninteractive apt install -y python3-rpi-lgpio
        fi
    fi
    log_success "Abhängigkeiten installiert"

    # ── Schritt 4: Repository vorbereiten ──
    run_step "Schritt 4/8: Repository vorbereiten" true
    verify_repo
    cd "$REPO_DIR"
    SCRIPT_DIR="$REPO_DIR"
    PATCHES_SRC_DIR="$REPO_DIR"
    log_success "Repository bereit"

    # ── Schritt 5: GPIO ──
    run_step "Schritt 5/8: GPIO-Konfiguration" configure_gpio

    # ── Schritt 6: PHP ──
    run_step "Schritt 6/8: PHP konfigurieren" configure_php

    # ── Schritt 7: Python ──
    case "$MODE" in
        venv)
            run_step "Schritt 7/8: Python venv erstellen" do_python_venv
            ;;
        python39)
            run_step "Schritt 7/8: Python 3.9.25 kompilieren" do_python_39
            ;;
        python314)
            run_step "Schritt 7/8: Python 3.14.4 kompilieren + venv" do_python_314
            ;;
    esac

    # ── Schritt 8: OpenWB ──
    run_step "Schritt 8/8: OpenWB installieren + patches" true
    do_openwb_install
    do_runtime_patches
    ensure_pip3_wrapper
    fix_openwb_homedir
    install_boot_service
    do_post_update_hook

    # Bereits aktivierte Feature-Patches anwenden (ohne Menü)
    patches_apply_enabled

    # Services starten
    log "Starte Services..."
    run_cmd sudo systemctl daemon-reload
    for svc in mosquitto mosquitto_local; do
        run_cmd sudo systemctl enable "$svc" 2>/dev/null || true
        run_cmd sudo systemctl restart "$svc" 2>/dev/null || true
    done
    run_cmd sudo systemctl enable openwb2 2>/dev/null || true
    run_cmd sudo systemctl restart openwb2 2>/dev/null || true
    sleep 3
    run_cmd sudo systemctl restart openwb-simpleAPI 2>/dev/null || true

    # Finale Überprüfung
    do_final_check
}

main "$@"
