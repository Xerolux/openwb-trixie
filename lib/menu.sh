#!/bin/bash

ensure_bubbletea_menu_tool() {
    if command -v gum >/dev/null 2>&1; then
        return 0
    fi

    if command -v apt-get >/dev/null 2>&1; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gum >/dev/null 2>&1 || true
    fi

    command -v gum >/dev/null 2>&1
}

ensure_native_bubbletea_menu() {
    local menu_bin="/tmp/openwb-bubbletea-menu"
    local menu_src="${LIB_DIR}/bubbletea_menu.go"

    if [ -x "$menu_bin" ]; then
        echo "$menu_bin"
        return 0
    fi

    if ! command -v go >/dev/null 2>&1; then
        return 1
    fi
    if [ ! -f "$menu_src" ]; then
        return 1
    fi

    (cd "$LIB_DIR" && timeout 20s go mod download >/tmp/openwb-bubbletea-build.log 2>&1 || true)
    (cd "$LIB_DIR" && timeout 20s go build -o "$menu_bin" "$menu_src" >>/tmp/openwb-bubbletea-build.log 2>&1 || true)

    if [ -x "$menu_bin" ]; then
        echo "$menu_bin"
        return 0
    fi
    log_warning "Bubble Tea Build fehlgeschlagen, Fallback auf gum/whiptail/text. Log: /tmp/openwb-bubbletea-build.log"
    return 1
}

bubbletea_main_menu() {
    local menu_bin
    menu_bin="$(ensure_native_bubbletea_menu || true)"
    if [ -z "$menu_bin" ] || [ ! -x "$menu_bin" ]; then
        echo "quit"
        return
    fi
    "$menu_bin"
}

gum_main_menu() {
    local sys_py selection _gum_tmp
    sys_py=$(python3 --version 2>&1 | awk '{print $2}')
    _gum_tmp=$(mktemp)

    gum choose --header "OpenWB Installer v${INSTALLER_VERSION} (Build ${BUILD_ID})" \
        "1) System-Python + venv [EMPFOHLEN] (Python ${sys_py})" \
        "2) Python 3.9.25 kompilieren [ORIGINAL]" \
        "3) Python 3.14.4 + venv [NEUESTE]" \
        "4) Feature-Patches verwalten" \
        "5) Legacy Wallbox Module" \
        "6) Tools installieren" \
        "7) Status anzeigen" \
        "8) Diagnose-Archiv erstellen" \
        "9) Diagnose anonymisieren + hochladen" \
        "10) Beenden" > "$_gum_tmp" 2>/dev/null < /dev/tty || true
    selection=$(cat "$_gum_tmp")
    rm -f "$_gum_tmp"

    case "$selection" in
        "1)"* )  echo "venv" ;;
        "2)"* )  echo "python39" ;;
        "3)"* )  echo "python314" ;;
        "4)"* )  echo "patches" ;;
        "5)"* )  echo "legacy_wallbox" ;;
        "6)"* )  echo "tools" ;;
        "7)"* )  echo "status" ;;
        "8)"* )  echo "diagnose" ;;
        "9)"* )  echo "diagnose_upload" ;;
        "10)"* ) echo "quit" ;;
        * )      echo "quit" ;;
    esac
}

ensure_whiptail() {
    if ! test -t 0 2>/dev/null || ! test -t 1 2>/dev/null; then
        return 1
    fi
    if command -v whiptail >/dev/null 2>&1; then
        return 0
    fi
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y whiptail 2>/dev/null
    command -v whiptail >/dev/null 2>&1
}

whiptail_main_menu() {
    local sys_py
    sys_py=$(python3 --version 2>&1 | awk '{print $2}')

    local sel
    sel=$(whiptail --title "OpenWB · Debian Trixie Installer v${INSTALLER_VERSION}" \
        --cancel-button "Beenden" \
        --menu "\nInstallationsoption wählen:\n\nBuild: ${BUILD_ID}" 25 78 10 \
        "1" "System-Python + venv       [EMPFOHLEN]  Python ${sys_py}" \
        "2" "Python 3.9.25 kompilieren   [ORIGINAL]   ~30-60 Min" \
        "3" "Python 3.14.4 + venv        [NEUESTE]    ~30-60 Min" \
        "4" "Feature-Patches verwalten" \
        "5" "Legacy Wallbox Module  !!EXPERIMENTAL!!" \
        "6" "Tools installieren" \
        "7" "Status anzeigen" \
        "8" "Diagnose-Archiv erstellen" \
        "9" "Diagnose anonymisieren + hochladen" \
        "10" "Beenden" \
        3>&1 1>&2 2>&3)

    local rc=$?
    [ $rc -ne 0 ] && echo "quit" && return

    case "$sel" in
        1)  echo "venv" ;;
        2)  echo "python39" ;;
        3)  echo "python314" ;;
        4)  echo "patches" ;;
        5)  echo "legacy_wallbox" ;;
        6)  echo "tools" ;;
        7)  echo "status" ;;
        8)  echo "diagnose" ;;
        9)  echo "diagnose_upload" ;;
        10) echo "quit" ;;
        "") echo "venv" ;;
        *)  echo "quit" ;;
    esac
}

text_main_menu() {
    local sys_py
    sys_py=$(python3 --version 2>&1 | awk '{print $2}')

    echo ""
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │              Was möchtest du tun?                        │"
    echo "  ├──────────────────────────────────────────────────────────┤"
    echo "  │                                                          │"
    echo "  │   [1]  System-Python + venv              EMPFOHLEN      │"
    echo "  │        Python ${sys_py} · Pakete isoliert im venv              │"
    echo "  │        Dauer: ca. 10-15 Minuten                          │"
    echo "  │                                                          │"
    echo "  │   [2]  Python 3.9.25 kompilieren          ORIGINAL       │"
    echo "  │        Kompiliert aus Quellcode, ersetzt System-Python   │"
    echo "  │        Dauer: ca. 30-60 Minuten                          │"
    echo "  │                                                          │"
    echo "  │   [3]  Python 3.14.4 kompilieren + venv   NEUESTE        │"
    echo "  │        Neuestes Python als Zusatz-Installation           │"
    echo "  │        Dauer: ca. 30-60 Minuten                          │"
    echo "  │                                                          │"
    echo "  │   [4]  Feature-Patches verwalten                         │"
    echo "  │                                                          │"
    echo "  │   [5]  Legacy Wallbox Module  !!EXPERIMENTAL!!          │"
    echo "  │        go-e / KEBA / SimpleEVSE evcc-optimiert           │"
    echo "  │                                                          │"
    echo "  │   [6]  Tools installieren (modbus-proxy u.a.)            │"
    echo "  │                                                          │"
    echo "  │   [7]  Status anzeigen                                   │"
    echo "  │                                                          │"
    echo "  │   [8]  Diagnose-Archiv erstellen                        │"
    echo "  │                                                          │"
    echo "  │   [9]  Diagnose anonymisieren + hochladen               │"
    echo "  │                                                          │"
    echo "  │  [10]  Beenden                           build:${BUILD_ID} │"
    echo "  │                                                          │"
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""

    while true; do
        read -p "  Deine Wahl [1/2/3/4/5/6/7/8/9/10]: " -n 2 -r < /dev/tty
        echo
        case "$REPLY" in
            1|"") echo "venv"; return ;;
            2)    echo "python39"; return ;;
            3)    echo "python314"; return ;;
            4)    echo "patches"; return ;;
            5)    echo "legacy_wallbox"; return ;;
            6)    echo "tools"; return ;;
            7)    echo "status"; return ;;
            8)    echo "diagnose"; return ;;
            9)    echo "diagnose_upload"; return ;;
            10|q|Q) echo "quit"; return ;;
            *)    echo "  Bitte 1-10 eingeben" ;;
        esac
    done
}
