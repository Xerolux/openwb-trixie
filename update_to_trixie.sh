#!/bin/bash

# Debian Bookworm zu Trixie Update Script
# WARNUNG: Führe dieses Script nur aus, wenn du verstehst, was es tut!
# Erstelle vorher ein Backup deines Systems!

set -e  # Script bei Fehlern beenden

echo "=== Debian Bookworm zu Trixie Update ==="
echo "WARNUNG: Dieses Script führt ein Major-Version-Update durch!"
echo "Stelle sicher, dass du ein vollständiges System-Backup hast."
echo ""
read -p "Möchtest du fortfahren? (j/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Update abgebrochen."
    exit 1
fi

echo ""
echo "=== Schritt 1: Aktuelle Paketliste aktualisieren ==="
sudo apt update
sudo apt upgrade -y

echo ""
echo "=== Schritt 2: Sources.list Backup erstellen ==="
sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)
if [ -f /etc/apt/sources.list.d/raspi.list ]; then
    sudo cp /etc/apt/sources.list.d/raspi.list /etc/apt/sources.list.d/raspi.list.backup.$(date +%Y%m%d_%H%M%S)
fi

echo ""
echo "=== Schritt 3: Repositories von Bookworm auf Trixie umstellen ==="
sudo sed -i 's/bookworm/trixie/g' /etc/apt/sources.list

# Prüfe ob raspi.list existiert (für Raspberry Pi)
if [ -f /etc/apt/sources.list.d/raspi.list ]; then
    echo "Raspberry Pi Repository gefunden, aktualisiere..."
    sudo sed -i 's/bookworm/trixie/g' /etc/apt/sources.list.d/raspi.list
fi

# Prüfe andere .list Dateien in sources.list.d
echo "Prüfe weitere Repository-Dateien..."
for file in /etc/apt/sources.list.d/*.list; do
    if [ -f "$file" ] && [ "$(basename "$file")" != "raspi.list" ]; then
        if grep -q "bookworm" "$file"; then
            echo "Aktualisiere $file..."
            sudo sed -i 's/bookworm/trixie/g' "$file"
        fi
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
echo "Bei Problemen kannst du das Backup wiederherstellen:"
echo "sudo cp /etc/apt/sources.list.backup.* /etc/apt/sources.list"

# Aktuelle Debian-Version anzeigen
echo ""
echo "=== Aktuelle System-Information ==="
lsb_release -a 2>/dev/null || cat /etc/debian_version
