#!/bin/bash

# Debian Bookworm zu Trixie Update Script
# WARNUNG: Führe dieses Script nur aus, wenn du verstehst, was es tut!
# Erstelle vorher ein Backup deines Systems!

set -Ee -o pipefail  # Script bei Fehlern beenden

on_error() {
    local exit_code="$1"
    local line_no="$2"
    local cmd="$3"
    echo "FEHLER in Zeile $line_no: $cmd (Exit-Code: $exit_code)"
    echo "Hinweis: Backups wurden unter '*.backup.<timestamp>' abgelegt."
    echo "Prüfe Netz/apt-Lock und starte den Schritt erneut."
}

trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

# Hilfe anzeigen
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Debian Bookworm zu Trixie Update Script"
    echo ""
    echo "Verwendung: $0 [OPTIONEN]"
    echo ""
    echo "Optionen:"
    echo "  --help, -h    Zeigt diese Hilfe"
    echo ""
    echo "Dieses Script führt folgende Schritte durch:"
    echo "  1. Aktuelle Paketliste aktualisieren"
    echo "  2. Backup der sources.list erstellen"
    echo "  3. Repositories von Bookworm auf Trixie umstellen"
    echo "  4. Vollständiges System-Upgrade (apt full-upgrade)"
    echo "  5. Aufräumen (autoremove, autoclean)"
    echo ""
    echo "WARNUNG: Dies ist ein Major-Version-Update!"
    echo "Erstelle vorher ein vollständiges System-Backup!"
    exit 0
fi

echo "=== Debian Bookworm zu Trixie Update ==="
echo "WARNUNG: Dieses Script führt ein Major-Version-Update durch!"
echo "Stelle sicher, dass du ein vollständiges System-Backup hast."
echo ""
read -p "Möchtest du fortfahren? (j/N): " -n 1 -r
echo
if [[ ! "$REPLY" =~ ^[Jj]$ ]]; then
    echo "Update abgebrochen."
    exit 1
fi

echo ""
echo "=== Schritt 1: Aktuelle Paketliste aktualisieren ==="
sudo apt update
sudo apt upgrade -y

echo ""
echo "=== Schritt 2: Sources.list Backup erstellen ==="
backup_ts=$(date +%Y%m%d_%H%M%S)
source_files=()

if [ -f /etc/apt/sources.list ]; then
    source_files+=("/etc/apt/sources.list")
fi

shopt -s nullglob
for file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    source_files+=("$file")
done
shopt -u nullglob

if [ ${#source_files[@]} -eq 0 ]; then
    echo "FEHLER: Keine APT-Quellen gefunden (weder sources.list noch *.sources/*.list)"
    exit 1
fi

for file in "${source_files[@]}"; do
    sudo cp "$file" "${file}.backup.${backup_ts}"
done

echo ""
echo "=== Schritt 3: Repositories von Bookworm auf Trixie umstellen ==="
for file in "${source_files[@]}"; do
    if grep -q "bookworm" "$file"; then
        echo "Aktualisiere $file..."
        sudo sed -i 's/bookworm/trixie/g' "$file"
    else
        echo "Keine bookworm-Einträge in $file gefunden, überspringe..."
    fi
done

echo ""
echo "=== Schritt 4: Paketliste mit neuen Repositories aktualisieren ==="
sudo apt update

echo ""
echo "=== Schritt 5: Vollständiges System-Upgrade durchführen ==="
echo "Dies kann eine Weile dauern..."
sudo apt full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew"

echo ""
echo "=== Schritt 6: Aufräumen ==="
sudo apt autoremove -y
sudo apt autoclean

echo ""
echo "=== Schritt 7: Neuen Kernel aktivieren (falls aktualisiert) ==="
if [ -f /var/run/reboot-required ]; then
    echo "Ein Neustart ist erforderlich, um das Update abzuschließen."
    echo "Führe 'sudo reboot' aus, wenn du bereit bist."
else
    echo "Kein Neustart erforderlich."
fi

echo ""
echo "=== Update abgeschlossen! ==="
echo "Prüfe die neue Version mit: lsb_release -a"
echo "Backups wurden mit Endung .backup.${backup_ts} erstellt."
echo "Beispiel für Restore:"
echo "sudo cp /etc/apt/sources.list.d/debian.sources.backup.${backup_ts} /etc/apt/sources.list.d/debian.sources"

# Aktuelle Debian-Version anzeigen
echo ""
echo "=== Aktuelle System-Information ==="
lsb_release -a 2>/dev/null || cat /etc/debian_version
