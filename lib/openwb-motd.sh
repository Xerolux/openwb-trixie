#!/bin/bash
# OpenWB Status MOTD - zeigt System-Status bei jedem Login
# Install: sudo cp openwb-motd.sh /usr/local/bin/openwb-status && sudo chmod +x /usr/local/bin/openwb-status
#          echo '/usr/local/bin/openwb-status' | sudo tee -a /etc/profile.d/openwb-motd.sh >/dev/null

VENV_DIR="${VENV_DIR:-/opt/openwb-venv}"
OPENWB_DIR="${OPENWB_DIR:-/var/www/html/openWB}"
OPENWB_USER="${OPENWB_USER:-openwb}"
REPO_DIR="/home/$OPENWB_USER/openwb-trixie"
BUILD_ID="${BUILD_ID:-unknown}"

is_raspberry_pi() {
    [ -f /proc/device-tree/model ] && grep -q "Raspberry Pi" /proc/device-tree/model
}

is_arm_arch() {
    [ "$(uname -m)" = "armv7l" ] || [ "$(uname -m)" = "aarch64" ]
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
    echo -e "  ${BB}│${W}  ${BOLD}Architektur:${W}  $(uname -m)$(is_raspberry_pi && echo " ${CY}(Raspberry Pi)${W}" || true)"

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
        current_build=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null)
    elif [ -d "$REPO_DIR" ]; then
        current_build="${BUILD_ID}"
    fi
    current_build="${current_build:-?}"

    local remote_build
    remote_build=$(git ls-remote --refs https://github.com/Xerolux/openwb-trixie.git HEAD 2>/dev/null | awk '{print substr($1,1,7)}')

    if [ -n "$current_build" ] && [ "$current_build" != "?" ]; then
        echo -e "  ${BB}│${W}    ${BOLD}Installiert:${W}  ${BG}${current_build}${W}"
    else
        echo -e "  ${BB}│${W}    ${BOLD}Installiert:${W}  ${RED}?${W}"
    fi

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
        owb_ver=$(git -C "$OPENWB_DIR" log -1 --format='%h %cs' 2>/dev/null)
        if [ -n "$owb_ver" ]; then
            echo -e "  ${BB}│${W}    ${BOLD}Version:${W}     ${GR}$owb_ver${W}"
        else
            echo -e "  ${BB}│${W}    ${BOLD}Status:${W}       ${GR}installiert${W}"
        fi
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

    echo -e "  ${BB}├─────────────────────────────────────────────────────────────┤${W}"
    echo -e "  ${BB}│${W}  ${BOLD}Werkzeuge:${W}"
    echo -e "  ${BB}│${W}    ${CY}openwb-status${W}          Diese Übersicht anzeigen"
    echo -e "  ${BB}│${W}    ${CY}openwb-logs${W}            Logs anzeigen (Falls verfügbar)"
    echo -e "  ${BB}│${W}    ${CY}openwb-restart${W}         Services neu starten"
    echo -e "  ${BB}│${W}"
    echo -e "  ${BB}│${W}  Web-Interface: ${CY}http://${ip_addr}${W}"
    echo -e "  ${BB}└─────────────────────────────────────────────────────────────┘${W}"
    echo ""
}

# Nur einmal pro Session anzeigen (via ENV-Variable)
if [ -z "$OPENWB_MOTD_SHOWN" ]; then
    export OPENWB_MOTD_SHOWN=1
    show_status
fi
