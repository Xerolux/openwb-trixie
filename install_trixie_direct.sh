#!/bin/bash

# OpenWB Installation für frische Debian Trixie Systeme
#
# Dieses Script ist optimiert für Systeme die BEREITS Trixie verwenden
# (kein Upgrade von Bookworm nötig)
#
# Nutzt System-Python mit venv - KEINE Python-Kompilierung!
# Spart 30-60 Minuten Installationszeit!

set -Ee -o pipefail  # Script bei Fehlern beenden

# Hilfe anzeigen
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "OpenWB Installation für Debian Trixie"
    echo ""
    echo "Verwendung: $0 [OPTIONEN]"
    echo ""
    echo "Optionen:"
    echo "  --help, -h    Zeigt diese Hilfe"
    echo ""
    echo "Dieses Script ist für FRISCHE Debian Trixie Installationen!"
    echo ""
    echo "Was wird gemacht:"
    echo "  1. System aktualisieren"
    echo "  2. Build-Abhängigkeiten installieren (SWIG, gcc, etc.)"
    echo "  3. Repository vorbereiten"
    echo "  4. GPIO-Konfiguration"
    echo "  5. PHP konfigurieren"
    echo "  6. Virtual Environment mit System-Python erstellen"
    echo "  7. OpenWB Installation"
    echo "  8. Post-Update Hook einrichten"
    echo ""
    echo "Vorteile:"
    echo "  - Keine Python-Kompilierung (spart 30-60 Min!)"
    echo "  - Nutzt modernes Debian Trixie Python (3.12+)"
    echo "  - Installation in ~10-15 Minuten"
    echo ""
    echo "Für Bookworm -> Trixie Upgrade nutze: install_complete.sh"
    exit 0
fi

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging-Funktionen
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
    log_error "Häufige Ursachen: fehlendes sudo-Recht, apt-Lock, Netzwerkproblem oder PEP668-Fehler im OpenWB-Installer."
}

trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

# Benutzer vorbereiten und Installer im openwb-Kontext fortsetzen
OPENWB_USER="openwb"
OPENWB_TRIXIE_SCRIPT_URL="${OPENWB_TRIXIE_SCRIPT_URL:-https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_trixie_direct.sh}"
INSTALLER_VERSION="2026-05-01.22"

ensure_openwb_user() {
    if id "$OPENWB_USER" >/dev/null 2>&1; then
        log "Benutzer '$OPENWB_USER' existiert bereits"
    else
        log "Lege Benutzer '$OPENWB_USER' an..."
        sudo useradd -m -s /bin/bash "$OPENWB_USER"
        log_success "Benutzer '$OPENWB_USER' wurde angelegt"
    fi

    if id -nG "$OPENWB_USER" | grep -qw sudo; then
        log "Benutzer '$OPENWB_USER' ist bereits in der Gruppe sudo"
    else
        log "Füge Benutzer '$OPENWB_USER' zur Gruppe sudo hinzu..."
        sudo usermod -aG sudo "$OPENWB_USER"
        log_success "Benutzer '$OPENWB_USER' wurde zur Gruppe sudo hinzugefügt"
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

switch_to_openwb_if_needed() {
    if [ "${OPENWB_RUN_AS_USER:-0}" = "1" ]; then
        return 0
    fi

    ensure_openwb_user

    if [ "$(id -un)" = "$OPENWB_USER" ]; then
        export OPENWB_RUN_AS_USER=1
        return 0
    fi

    ensure_openwb_password_for_sudo

    log "Starte Installer als Benutzer '$OPENWB_USER' neu..."
    if [ -f "$0" ] && [ -r "$0" ]; then
        exec sudo -H -u "$OPENWB_USER" env OPENWB_RUN_AS_USER=1 bash "$0" "$@"
    fi

    log_warning "Installer läuft vermutlich via Pipe (curl | bash), nutze Fallback über Raw-URL"
    exec sudo -H -u "$OPENWB_USER" env OPENWB_RUN_AS_USER=1 OPENWB_TRIXIE_SCRIPT_URL="$OPENWB_TRIXIE_SCRIPT_URL" \
        bash -lc 'curl -fsSL "${OPENWB_TRIXIE_SCRIPT_URL}?ts=$(date +%s)" | bash'
}

# PHP-Version dynamisch ermitteln
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
    else
        log_warning "openwb2.service nicht gefunden: $service_file"
    fi

    if [ -f "$atreboot_file" ]; then
        log "Passe atreboot.sh auf venv-pip an (PEP668-sicher)..."
        sudo sed -i "s#\\([^[:alnum:]_/.-]\\|^\\)pip3 install -r#\\1$venv_pip install -r#g" "$atreboot_file"
    else
        log_warning "atreboot.sh nicht gefunden: $atreboot_file"
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

show_service_status() {
    log "=== Service-Status (Kurzcheck) ==="
    if command -v systemctl >/dev/null 2>&1; then
        for service in mosquitto openwb2 openwb-simpleAPI; do
            if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
                status=$(systemctl is-active "$service" 2>/dev/null || true)
                if [ "$status" = "active" ]; then
                    log_success "$service ist aktiv"
                else
                    log_warning "$service ist nicht aktiv (Status: ${status:-unbekannt})"
                fi
            fi
        done
    else
        log_warning "systemctl nicht verfügbar - Statuscheck übersprungen"
    fi
}

ensure_openwb_runtime_prereqs() {
    log "Installiere Laufzeit-Tools (usbutils, dnsmasq)..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y usbutils dnsmasq || log_warning "Konnte usbutils/dnsmasq nicht vollständig installieren"

    if getent group gpio >/dev/null 2>&1; then
        log "Gruppe 'gpio' existiert bereits"
    else
        log "Lege fehlende Gruppe 'gpio' an..."
        sudo groupadd gpio || true
    fi
    sudo usermod -aG gpio "$OPENWB_USER" || true
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

configure_german_defaults() {
    log "Setze Zeitzone auf Europe/Berlin..."
    sudo timedatectl set-timezone Europe/Berlin 2>/dev/null || sudo ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
    sudo sh -c 'echo "Europe/Berlin" > /etc/timezone'

    log "Installiere/aktualisiere Locale- und Keyboard-Pakete..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y locales keyboard-configuration console-setup tzdata

    log "Setze Locale auf de_DE.UTF-8..."
    if ! grep -q '^de_DE.UTF-8 UTF-8$' /etc/locale.gen; then
        echo 'de_DE.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen > /dev/null
    fi
    sudo locale-gen de_DE.UTF-8
    sudo update-locale LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8

    log "Setze Tastatur-Layout auf Deutsch..."
    {
        echo 'keyboard-configuration keyboard-configuration/layoutcode select de'
        echo 'keyboard-configuration keyboard-configuration/modelcode select pc105'
        echo 'keyboard-configuration keyboard-configuration/variantcode select'
        echo 'keyboard-configuration keyboard-configuration/optionscode string'
    } | sudo debconf-set-selections
    sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration
    sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure console-setup
    sudo setupcon -k || true

    log_success "Zeitzone/Locale/Tastatur auf deutsche Standards gesetzt"
}

ensure_openwb_webroot() {
    sudo mkdir -p /var/www/html
    sudo chown root:root /var/www /var/www/html 2>/dev/null || true
}

recover_dpkg_if_needed() {
    if [ -f /var/lib/dpkg/lock-frontend ] || [ -f /var/lib/dpkg/lock ]; then
        true
    fi
    if sudo test -f /var/lib/dpkg/updates/0000 || sudo test -n "$(sudo find /var/lib/dpkg/updates -maxdepth 1 -type f 2>/dev/null)"; then
        log_warning "Unvollständiger dpkg-Status erkannt, repariere mit dpkg --configure -a..."
        sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a
    fi
}

ensure_free_space_mb() {
    local min_mb="$1"
    local avail_mb
    avail_mb=$(df -Pm / | awk 'NR==2 {print $4}')
    if [ -z "$avail_mb" ]; then
        log_warning "Konnte freien Speicher nicht ermitteln"
        return 0
    fi
    if [ "$avail_mb" -lt "$min_mb" ]; then
        log_error "Zu wenig freier Speicher auf / (${avail_mb} MB, benötigt mindestens ${min_mb} MB)"
        log_error "Bitte Platz schaffen (z. B. apt clean, alte Logs/Downloads löschen) und erneut starten."
        exit 1
    fi
    log "Freier Speicher auf /: ${avail_mb} MB"
}

prepare_openwb_requirements_for_py313() {
    local req_file="/var/www/html/openWB/requirements.txt"
    if [ -f "$req_file" ]; then
        log "Passe OpenWB requirements für Python 3.13 an..."
        sudo sed -E -i \
            -e 's/^jq==[0-9]+\.[0-9]+\.[0-9]+([[:space:]]*)$/# jq entfernt auf Python 3.13 (System-jq via apt)\1/' \
            -e 's/^lxml==4\.9\.[0-9]+([[:space:]]*)$/lxml==5.3.2\1/' \
            -e 's/^grpcio==1\.60\.1([[:space:]]*)$/grpcio==1.71.0\1/' \
            "$req_file"
    fi

    if [ -x /opt/openwb-venv/bin/pip3 ]; then
        log "Aktualisiere pip/setuptools/wheel im venv..."
        /opt/openwb-venv/bin/pip3 install -U pip setuptools wheel
    fi
}

patch_openwb_runtime_scripts() {
    local openwb_dir="$1"
    local atreboot_file="$openwb_dir/runs/atreboot.sh"

    if [ -f "$atreboot_file" ]; then
        log "Patch: atreboot.sh auf venv-pip (PEP668-sicher)..."
        sudo sed -i -E 's@(^|[^[:alnum:]_/.-])pip3[[:space:]]+install[[:space:]]+-r@\1/opt/openwb-venv/bin/pip3 install -r@g' "$atreboot_file"
        sudo chmod +x "$atreboot_file"
    fi
}

cleanup_venv_artifacts() {
    local sp="/opt/openwb-venv/lib/python3.13/site-packages"
    if [ -d "$sp" ]; then
        log "Bereinige verwaiste venv-Artefakte (~*)..."
        sudo find "$sp" -maxdepth 1 -name '~*' -exec rm -rf {} + 2>/dev/null || true
    fi
}

run_openwb_core_installer_noninteractive() {
    local tmp_dir install_script packages_script
    tmp_dir=$(mktemp -d)
    install_script="$tmp_dir/openwb-install.sh"
    packages_script="$tmp_dir/install_packages.sh"
    trap 'rm -rf "$tmp_dir"' RETURN

    curl -fsSL https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh -o "$install_script"
    curl -fsSL https://raw.githubusercontent.com/openWB/core/master/runs/install_packages.sh -o "$packages_script"

    # Upstream-Skripte robust machen:
    # 1) Paketinstallation strikt non-interaktiv
    # 2) /var/www/html/openWB mit mkdir -p anlegen
    sed -i \
        -e 's|sudo apt-get -q update|sudo DEBIAN_FRONTEND=noninteractive apt-get -q update|g' \
        -e 's|sudo apt-get -q -y install|sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install|g' \
        "$packages_script"

    sed -i \
        -e "s@curl -s \"https://raw.githubusercontent.com/openWB/core/master/runs/install_packages.sh\" | bash -s@bash \"$packages_script\"@g" \
        -e 's@mkdir "$OPENWBBASEDIR"@mkdir -p "$OPENWBBASEDIR"@g' \
        -e 's@sudo -u "\$OPENWB_USER" pip install -r "\${OPENWBBASEDIR}/requirements.txt"@sed -i -E '\''s/^jq==[0-9]+\\.[0-9]+\\.[0-9]+([[:space:]]*)$/# jq entfernt auf Python 3.13 (System-jq via apt)\\1/; s/^lxml==4\\.9\\.[0-9]+([[:space:]]*)$/lxml==5.3.2\\1/; s/^grpcio==1\\.60\\.1([[:space:]]*)$/grpcio==1.71.0\\1/'\'' "\${OPENWBBASEDIR}/requirements.txt"; /opt/openwb-venv/bin/pip3 install -U pip setuptools wheel; /opt/openwb-venv/bin/pip3 install -r "\${OPENWBBASEDIR}/requirements.txt"@g' \
        -e 's@^/usr/sbin/groupadd "\$OPENWB_GROUP"$@/usr/sbin/groupadd "\$OPENWB_GROUP" || true@g' \
        -e 's@^/usr/sbin/useradd "\$OPENWB_USER" -g "\$OPENWB_GROUP" --create-home$@/usr/sbin/useradd "\$OPENWB_USER" -g "\$OPENWB_GROUP" --create-home || true@g' \
        -e 's@^ln -s "\${OPENWBBASEDIR}/data/config/openwb2.service" /etc/systemd/system/openwb2.service$@ln -sfn "\${OPENWBBASEDIR}/data/config/openwb2.service" /etc/systemd/system/openwb2.service@g' \
        -e 's@^ln -s "\${OPENWBBASEDIR}/data/config/openwb-simpleAPI.service" /etc/systemd/system/openwb-simpleAPI.service$@ln -sfn "\${OPENWBBASEDIR}/data/config/openwb-simpleAPI.service" /etc/systemd/system/openwb-simpleAPI.service@g' \
        "$install_script"

    # Fallback: fange abweichende Upstream-Varianten des pip-Aufrufs ab
    sed -E -i \
        -e 's@(^[[:space:]]*sudo -u "\$OPENWB_USER"[[:space:]]+)pip([[:space:]]+install[[:space:]]+-r[[:space:]]+"\$\{OPENWBBASEDIR\}/requirements\.txt")@/opt/openwb-venv/bin/pip3\2@g' \
        -e 's@(^[[:space:]]*)pip([[:space:]]+install[[:space:]]+-r[[:space:]]+"\$\{OPENWBBASEDIR\}/requirements\.txt")@/opt/openwb-venv/bin/pip3\2@g' \
        "$install_script"

    # Fehler im Upstream-Installer hart stoppen, statt mit kaputtem Zustand weiterzulaufen
    sed -i '2i set -Eeuo pipefail' "$install_script"
    sudo DEBIAN_FRONTEND=noninteractive bash "$install_script"
}

echo "====================================================================="
echo "   OpenWB Installation für Debian Trixie"
echo "====================================================================="
echo "Version: $INSTALLER_VERSION"
echo ""
echo "Dieses Script installiert OpenWB auf einem FRISCHEN Trixie-System"
echo ""
echo "Was wird gemacht:"
echo "  1. System aktualisieren"
echo "  2. Build-Abhängigkeiten installieren (SWIG, gcc, etc.)"
echo "  3. Repository vorbereiten"
echo "  4. GPIO-Konfiguration"
echo "  5. PHP konfigurieren"
echo "  6. Virtual Environment mit System-Python (schnell!)"
echo "  7. OpenWB Installation"
echo "  8. Post-Update Hook einrichten"
echo ""
echo "Vorteile:"
echo "  ✓ Keine Python-Kompilierung (spart 30-60 Min!)"
echo "  ✓ Nutzt modernes Debian Trixie Python (3.12+)"
echo "  ✓ Isolierte Paket-Installation (venv)"
echo "  ✓ Überlebt OpenWB-Updates automatisch"
echo ""

switch_to_openwb_if_needed "$@"

# Prüfe ob bereits Trixie läuft
if ! is_trixie; then
    log_error "Dieses System läuft NICHT auf Debian Trixie!"
    echo ""
    echo "Optionen:"
    echo "  1. Nutze install_complete.sh für Upgrade von Bookworm zu Trixie"
    echo "  2. Führe zuerst update_to_trixie.sh aus"
    exit 1
fi

log_success "Debian Trixie erkannt"

# Schritt 1: System aktualisieren
log "=== Schritt 1: System aktualisieren ==="
recover_dpkg_if_needed
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

read -p "System ist aktualisiert. Mit den restlichen Schritten fortfahren? (j/N): " -n 1 -r < /dev/tty
echo
if [[ ! "$REPLY" =~ ^[Jj]$ ]]; then
    echo "Installation nach Systemupdate abgebrochen."
    exit 1
fi

# Schritt 0: Deutsche Standards setzen
log "=== Schritt 0: Deutsche Standards setzen (Zeitzone/Keyboard/UTF-8) ==="
recover_dpkg_if_needed
configure_german_defaults

# Schritt 2: Build-Abhängigkeiten installieren
log "=== Schritt 2: Build-Abhängigkeiten installieren ==="
log "Installiere SWIG und Entwicklungs-Tools für Python-Pakete..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    swig \
    build-essential \
    python3-dev \
    python3-pip \
    python3-venv \
    pkg-config \
    libgpiod-dev \
    libffi-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev

# Raspberry Pi-spezifische Pakete nur auf Raspberry Pi mit ARM/ARM64 installieren
if is_arm_arch && is_raspberry_pi; then
    if apt-cache show liblgpio-dev &>/dev/null; then
        sudo DEBIAN_FRONTEND=noninteractive apt install -y liblgpio-dev
        log_success "liblgpio-dev installiert"
    else
        log_warning "liblgpio-dev nicht verfügbar, überspringe"
    fi

    if apt-cache show python3-rpi-lgpio &>/dev/null; then
        sudo DEBIAN_FRONTEND=noninteractive apt install -y python3-rpi-lgpio
        log_success "python3-rpi-lgpio installiert"
    else
        log_warning "python3-rpi-lgpio nicht verfügbar, überspringe"
    fi
else
    log "Kein Raspberry Pi mit ARM/ARM64 erkannt, überspringe liblgpio-dev und python3-rpi-lgpio"
fi
log_success "Build-Abhängigkeiten erfolgreich installiert"
ensure_openwb_runtime_prereqs

# Schritt 3: Git installieren und Repository klonen (falls nicht vorhanden)
log "=== Schritt 3: Repository vorbereiten ==="

if [ ! -d "/home/openwb/openwb-trixie" ]; then
    log "Git installieren..."
    sudo apt install git -y

    log "Repository klonen..."
    sudo mkdir -p /home/openwb
    cd /home/openwb
    git clone https://github.com/Xerolux/openwb-trixie.git
    cd openwb-trixie
else
    log "Repository bereits vorhanden"
    cd /home/openwb/openwb-trixie
fi

# Schritt 4: GPIO-Konfiguration
log "=== Schritt 4: GPIO-Konfiguration ==="

if is_arm_arch && is_raspberry_pi; then
    # Ermittle korrekten config.txt Pfad (neu: /boot/firmware/, alt: /boot/)
    if [ -f "/boot/firmware/config.txt" ]; then
        CONFIG_TXT="/boot/firmware/config.txt"
    elif [ -f "/boot/config.txt" ]; then
        CONFIG_TXT="/boot/config.txt"
    else
        log_warning "config.txt nicht gefunden - GPIO-Konfiguration übersprungen"
        CONFIG_TXT=""
    fi
else
    log "Kein Raspberry Pi erkannt - GPIO-Konfiguration wird übersprungen"
    CONFIG_TXT=""
fi

if [ -n "$CONFIG_TXT" ]; then
    log "Konfiguriere $CONFIG_TXT für OpenWB..."
    sudo cp "$CONFIG_TXT" "${CONFIG_TXT}.backup.$(date +%Y%m%d_%H%M%S)"

    # Audio deaktivieren
    sudo sed -i 's/dtparam=audio=on/dtparam=audio=off/g' "$CONFIG_TXT"

    # vc4-kms-v3d auskommentieren
    sudo sed -i 's/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/g' "$CONFIG_TXT"

    # OpenWB Konfiguration hinzufügen (falls noch nicht vorhanden)
    if ! grep -q "# openwb - begin" "$CONFIG_TXT"; then
        log "Füge OpenWB-Konfiguration hinzu..."
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
        log_success "GPIO-Konfiguration hinzugefügt"
    else
        log "GPIO-Konfiguration bereits vorhanden"
    fi
fi

# Schritt 5: PHP Upload-Limits konfigurieren
log "=== Schritt 5: PHP konfigurieren ==="
PHP_VER=$(detect_php_version)
log "Erkannte PHP-Version: $PHP_VER"
sudo mkdir -p "/etc/php/$PHP_VER/apache2/conf.d/" 2>/dev/null || true
printf 'upload_max_filesize = 300M\npost_max_size = 300M\n' | sudo tee "/etc/php/$PHP_VER/apache2/conf.d/20-uploadlimit.ini" > /dev/null
log_success "PHP Upload-Limits auf 300M gesetzt (PHP $PHP_VER)"

# Schritt 6: Virtual Environment erstellen
log "=== Schritt 6: Virtual Environment Setup ==="
log "Nutzt System-Python - KEINE Kompilierung nötig!"

chmod +x install_python3.9.sh
# Non-interaktiver venv-Setup ohne Rückfragen
if OPENWB_VENV_NONINTERACTIVE=1 ./install_python3.9.sh --venv-only; then
    log_success "Virtual Environment erfolgreich erstellt"
    cleanup_venv_artifacts
else
    log_error "Fehler beim venv-Setup"
    exit 1
fi

# Schritt 7: OpenWB Installation
log "=== Schritt 7: OpenWB Installation ==="

# Prüfe ob OpenWB bereits installiert ist
if [ -f "/var/www/html/openWB/openwb.sh" ] || [ -f "/home/openwb/openwb/openwb.sh" ]; then
    log "OpenWB bereits installiert, überspringe..."
else
    log "OpenWB wird installiert..."
    ensure_free_space_mb 2500
    ensure_openwb_webroot
    prepare_openwb_requirements_for_py313
    run_openwb_core_installer_noninteractive
    log_success "OpenWB erfolgreich installiert"
fi

# PEP668/externally-managed vermeiden: OpenWB Runtime auf venv umstellen
OPENWB_RUNTIME_DIR=""
for candidate in "/var/www/html/openWB" "/home/openwb/openWB" "/home/openwb/openwb" "/opt/openWB"; do
    if [ -d "$candidate" ]; then
        OPENWB_RUNTIME_DIR="$candidate"
        break
    fi
done
if [ -n "$OPENWB_RUNTIME_DIR" ]; then
    configure_openwb_venv_runtime "$OPENWB_RUNTIME_DIR"
    patch_openwb_runtime_scripts "$OPENWB_RUNTIME_DIR"
    cleanup_venv_artifacts
fi

# Schritt 8: Post-Update Hook installieren
log "=== Schritt 8: Post-Update Hook einrichten ==="

if [ -f "openwb_post_update_hook.sh" ]; then
    OPENWB_DIRS=(
        "/var/www/html/openWB"
        "/home/openwb/openWB"
        "/opt/openWB"
    )

    for openwb_dir in "${OPENWB_DIRS[@]}"; do
        if [ -d "$openwb_dir" ]; then
            sudo mkdir -p "$openwb_dir/data/config"
            sudo cp openwb_post_update_hook.sh "$openwb_dir/data/config/post-update.sh"
            sudo chmod +x "$openwb_dir/data/config/post-update.sh"
            log_success "Post-Update Hook installiert: $openwb_dir/data/config/post-update.sh"
            break
        fi
    done
fi

# Finale Prüfung
log "=== Finale Überprüfung ==="

# System-Python prüfen
SYSTEM_PYTHON=$(python3 --version 2>/dev/null || echo "Fehler")
log "System Python: $SYSTEM_PYTHON"

# venv-Python prüfen
if [ -d "/opt/openwb-venv" ]; then
    source /opt/openwb-venv/bin/activate
    VENV_PYTHON=$(python --version 2>/dev/null || echo "Fehler")
    deactivate
    log "venv Python: $VENV_PYTHON"
fi

# Trixie-Version prüfen
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    TRIXIE_VERSION="${VERSION_CODENAME:-${VERSION_ID:-unbekannt}}"
else
    TRIXIE_VERSION=$(lsb_release -c 2>/dev/null | awk '{print $2}' || cat /etc/debian_version)
fi
log "Debian Version: $TRIXIE_VERSION"

echo ""
echo "====================================================================="
echo "   Installation abgeschlossen!"
echo "====================================================================="
echo ""
echo "Zusammenfassung:"
echo "  ✓ Debian Trixie: $TRIXIE_VERSION"
echo "  ✓ System Python: $SYSTEM_PYTHON"
echo "  ✓ venv Python: ${VENV_PYTHON:-nicht installiert}"
echo "  ✓ Virtual Environment: /opt/openwb-venv"
echo "  ✓ Post-Update Hook: installiert"
echo ""
echo "Nächste Schritte:"
if is_arm_arch && is_raspberry_pi; then
    echo "  1. Neustart empfohlen für GPIO-Konfiguration:"
    echo "     sudo reboot"
    echo ""
    echo "  2. Nach Neustart - OpenWB Web-Interface öffnen:"
else
    echo "  1. OpenWB Web-Interface öffnen:"
fi
echo "     http://$(hostname -I | awk '{print $1}')"
echo ""
echo "  2. Python-Skripte mit venv ausführen:"
echo "     openwb-activate python script.py"
echo ""
echo "Vorteile dieser Installation:"
echo "  ✓ Keine Python-Kompilierung (30-60 Min gespart!)"
echo "  ✓ Nutzt modernes Trixie-Python (${SYSTEM_PYTHON})"
echo "  ✓ venv überlebt OpenWB-Updates automatisch"
echo "  ✓ Automatische venv-Updates nach OpenWB-Updates"
echo ""
echo "====================================================================="

show_service_status

if is_arm_arch && is_raspberry_pi; then
    log_warning "Ein Neustart wird empfohlen für GPIO-Konfiguration!"
    read -p "Jetzt neustarten? (j/N): " -n 1 -r < /dev/tty
    echo
    if [[ "$REPLY" =~ ^[Jj]$ ]]; then
        sudo reboot
    fi
fi
