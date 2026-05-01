#!/bin/bash

# OpenWB Post-Update Hook
# Dieses Script wird nach OpenWB-Updates ausgeführt, um das venv zu aktualisieren
# Installation: Kopiere dieses Script nach /var/www/html/openWB/data/config/post-update.sh
#               oder verlinke es entsprechend in das OpenWB-Update-System

set -Ee -o pipefail

on_error() {
    local exit_code="$1"
    local line_no="$2"
    local cmd="$3"
    echo -e "\033[0;31m[OpenWB-Hook] ✗\033[0m Fehler in Zeile $line_no: $cmd (Exit-Code: $exit_code)"
    # venv deaktivieren falls aktiv
    if [[ "$(type -t deactivate)" = "function" ]]; then
        deactivate 2>/dev/null || true
    fi
}

trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

# Hilfe anzeigen
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "OpenWB Post-Update Hook"
    echo ""
    echo "Verwendung: $0 [OPTIONEN]"
    echo ""
    echo "Optionen:"
    echo "  --help, -h    Zeigt diese Hilfe"
    echo ""
    echo "Dieses Script wird automatisch nach OpenWB-Updates ausgeführt."
    echo ""
    echo "Was wird gemacht:"
    echo "  1. Prüft ob venv existiert (/opt/openwb-venv)"
    echo "  2. Aktualisiert Python-Pakete aus requirements.txt"
    echo "  3. Startet OpenWB-Services neu (optional)"
    echo ""
    echo "Installation:"
    echo "  sudo cp openwb_post_update_hook.sh /var/www/html/openWB/data/config/post-update.sh"
    echo "  sudo chmod +x /var/www/html/openWB/data/config/post-update.sh"
    exit 0
fi

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
OPENWB_DIR="/var/www/html/openWB"
PATCH_DIR="/opt/openwb-patches"
PATCH_CONF="$PATCH_DIR/enabled.conf"
PATCHES_SRC_DIR="/home/openwb/openwb-trixie"

is_arm_arch() {
    case "$(uname -m 2>/dev/null || true)" in
        arm*|aarch64) return 0 ;;
        *) return 1 ;;
    esac
}

is_raspberry_pi() {
    [ -f /proc/device-tree/model ] && grep -qi "raspberry" /proc/device-tree/model 2>/dev/null
}

patch_get_field() {
    grep -m1 "^# $1:" "$2" 2>/dev/null | sed "s/^# $1: *//"
}

patch_matches_arch() {
    local file="$1"
    local arch
    arch=$(patch_get_field "Arch" "$file")
    [ -z "$arch" ] && return 0
    case "$arch" in
        arm)  is_arm_arch ;;
        rpi)  is_arm_arch && is_raspberry_pi ;;
        x86)  ! is_arm_arch ;;
        *)    return 0 ;;
    esac
}

reapply_openwb_patches() {
    local atreboot_file="$OPENWB_DIR/runs/atreboot.sh"
    local service_file="$OPENWB_DIR/data/config/openwb2.service"
    local simpleapi_service_file="$OPENWB_DIR/data/config/openwb-simpleAPI.service"
    local req_file="$OPENWB_DIR/requirements.txt"
    local venv_pip="/opt/openwb-venv/bin/pip3"
    local venv_python="/opt/openwb-venv/bin/python3"

    log "Setze update-feste OpenWB-Patches erneut..."

    if [ -f "$req_file" ]; then
        sed -E -i \
            -e 's/^jq==[0-9]+\.[0-9]+\.[0-9]+([[:space:]]*)$/# jq entfernt auf Python 3.13 (System-jq via apt)\1/' \
            -e 's/^lxml==4\.9\.[0-9]+([[:space:]]*)$/lxml==5.3.2\1/' \
            -e 's/^grpcio==1\.60\.1([[:space:]]*)$/grpcio==1.71.0\1/' \
            "$req_file"
        log_success "requirements.txt gepatcht"
    fi

    if [ -f "$atreboot_file" ]; then
        sed -i -E 's@(^|[^[:alnum:]_/.-])pip3[[:space:]]+install[[:space:]]+-r@\1/opt/openwb-venv/bin/pip3 install -r@g' "$atreboot_file"
        sed -i -E 's@(^|[^[:alnum:]_/.-])pip3[[:space:]]+install[[:space:]]+--only-binary@\1/opt/openwb-venv/bin/pip3 install --only-binary@g' "$atreboot_file"
        sed -i 's|pip uninstall urllib3 -y|/opt/openwb-venv/bin/pip3 uninstall urllib3 -y|g' "$atreboot_file"
        chmod +x "$atreboot_file"
        log_success "atreboot.sh gepatcht (venv-pip)"
    fi

    if [ -f "$service_file" ]; then
        sed -i "s#^ExecStart=.*main.py#ExecStart=$venv_python $OPENWB_DIR/packages/main.py#g" "$service_file"
        log_success "openwb2.service gepatcht (venv-python)"
    fi

    if [ -f "$simpleapi_service_file" ]; then
        sed -i -E 's@^ExecStart=.*simpleAPI_mqtt\.py$@ExecStart=/opt/openwb-venv/bin/python3 /var/www/html/openWB/simpleAPI/simpleAPI_mqtt.py@g' "$simpleapi_service_file"
        ln -sfn "$simpleapi_service_file" /etc/systemd/system/openwb-simpleAPI.service
        log_success "simpleAPI.service gepatcht (venv-python)"
    fi

    local shim_dir
    shim_dir=$(ls -d /opt/openwb-venv/lib/python3.*/site-packages 2>/dev/null | head -1)
    if [ -n "$shim_dir" ] && [ -d "$shim_dir" ] && [ ! -f "$shim_dir/openwb_py313_compat.py" ]; then
        printf 'import asyncio\nimport types\nimport sys\nif sys.version_info >= (3, 11) and not hasattr(asyncio, "coroutine"):\n    def _coroutine_compat(func):\n        return types.coroutine(func)\n    asyncio.coroutine = _coroutine_compat\n' > "$shim_dir/openwb_py313_compat.py"
        echo 'import openwb_py313_compat' > "$shim_dir/openwb_py313_compat.pth"
        log_success "asyncio.coroutine Kompatibilitaets-Shim installiert"
    fi

    if [ -f "/etc/init.d/mosquitto_local" ] && [ ! -f "/etc/systemd/system/mosquitto_local.service" ]; then
        cat > /etc/systemd/system/mosquitto_local.service <<'EOF'
[Unit]
Description=Mosquitto Local Instance (openWB)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/etc/init.d/mosquitto_local start
ExecStop=/etc/init.d/mosquitto_local stop
ExecReload=/etc/init.d/mosquitto_local restart
TimeoutSec=60
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable mosquitto_local >/dev/null 2>&1 || true
    fi

    # PHP Upload-Limit
    local php_ver
    php_ver=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null)
    if [ -n "$php_ver" ]; then
        local php_ini="/etc/php/$php_ver/apache2/conf.d/20-uploadlimit.ini"
        printf 'upload_max_filesize = 300M\npost_max_size = 300M\n' | sudo tee "$php_ini" > /dev/null 2>/dev/null || true
        log_success "PHP Upload-Limit gesetzt (300M)"
    fi
}

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
    elif apt-cache show python3-rpi-lgpio >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y python3-rpi-lgpio
    else
        log_warning "python3-rpi-lgpio nicht im APT-Repository verfügbar - überspringe Systempaket"
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
    if OPENWB_VENV_NONINTERACTIVE=1 bash "$SETUP_SCRIPT" --update; then
        log_success "venv erfolgreich aktualisiert"
    else
        log_error "Fehler beim venv-Update"
        exit 1
    fi
fi

reapply_openwb_patches

# Feature-Patches erneut anwenden
if [ -f "$PATCH_CONF" ] && [ -s "$PATCH_CONF" ]; then
    log "Wende aktivierte Feature-Patches erneut an..."
    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        pfile=""
        for f in "$PATCHES_SRC_DIR"/patches/*.sh; do
            [ -f "$f" ] || continue
            if grep -qm1 "^# Id: *$pid$" "$f"; then
                pfile="$f"
                break
            fi
        done
        if [ -z "$pfile" ]; then
            log_warning "Patch '$pid' nicht in $PATCHES_SRC_DIR/patches/"
            continue
        fi
        if ! patch_matches_arch "$pfile"; then
            log "  $pid: übersprungen (falsche Architektur)"
            continue
        fi
        export OPENWB_DIR VENV_DIR
        source "$pfile"
        if patch_check; then
            log "  $pid: bereits aktiv"
        else
            if patch_apply; then
                log_success "  $pid: erneut angewendet"
            else
                log_error "  $pid: FEHLER beim Re-Patch"
            fi
        fi
    done < "$PATCH_CONF"
else
    log "Keine Feature-Patches aktiviert"
fi

# Optional: Prüfe OpenWB-Services und starte neu
if command -v systemctl &> /dev/null; then
    log "Prüfe OpenWB-Services..."

    # Liste der möglichen OpenWB-Services (ohne .service-Suffix, systemctl erkennt beides)
    SERVICES=("openwb" "openwb2")

    for service in "${SERVICES[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null; then
            log "Starte $service neu..."
            sudo systemctl restart "$service" || log_warning "Konnte $service nicht neustarten"
        fi
    done
fi

log_success "=== Post-Update Hook abgeschlossen ==="
exit 0
