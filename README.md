# OpenWB auf Debian Trixie Installation - Komplette Anleitung

## Schritt 1: Raspberry Pi OS Bookworm Light 64-bit installieren

### 1.1 Raspberry Pi Imager vorbereiten
- Lade den **Raspberry Pi Imager** herunter und installiere ihn
- Starte den Imager

### 1.2 OS auswählen und konfigurieren
- Wähle **"Raspberry Pi OS (64-bit)"** → **"Raspberry Pi OS Lite (64-bit)"**
- Klicke auf das **Zahnrad-Symbol** (Erweiterte Optionen)
- Konfiguriere folgende Einstellungen:
  - ✅ **SSH aktivieren** (mit Passwort-Authentifizierung)
  - ✅ **Benutzername und Passwort setzen**:
    - Benutzername: `openwb`
    - Passwort: (dein gewähltes Passwort)
  - ✅ **WLAN konfigurieren** (falls gewünscht)
  - ✅ **Locale-Einstellungen**: Zeitzone auf `Europe/Berlin` setzen

### 1.3 Installation durchführen
- Wähle deine SD-Karte aus
- Klicke auf **"Schreiben"** und warte bis der Vorgang abgeschlossen ist
- Stecke die SD-Karte in den Raspberry Pi und starte ihn

## Schritt 2: Ersten Login und System vorbereiten

### 2.1 SSH-Verbindung herstellen
Verwende **PuTTY** oder ein anderes SSH-Client:
- Öffne PuTTY
- Hostname: `[IP-ADRESSE-DES-PI]`
- Port: 22
- Connection Type: SSH
- Klicke auf "Open"
- Login mit Benutzername `openwb` und deinem Passwort

### 2.2 Benutzer zu sudo-Gruppe hinzufügen
```bash
# Falls noch nicht automatisch geschehen:
sudo usermod -aG sudo openwb
```

### 2.3 System auf neueste Bookworm-Version aktualisieren
```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

## Schritt 3: Repository klonen und Update auf Trixie

### 3.1 Git installieren und Repository klonen
```bash
sudo apt install git -y
git clone https://github.com/Xerolux/openwb-trixie.git
cd openwb-trixie
```

### 3.2 Update auf Debian Trixie durchführen
```bash
chmod +x update_to_trixie.sh
./update_to_trixie.sh
```

**Wichtige Hinweise zum Trixie-Update:**
- Das Script erstellt automatisch Backups der Repository-Listen
- Bestätige die Abfrage mit `j` (ja)
- Der Vorgang kann 30-60 Minuten dauern
- **Nach dem Update ist ein Neustart erforderlich!**

### 3.3 Neustart nach Trixie-Update
```bash
sudo reboot
```

### 3.4 Trixie-Installation überprüfen
```bash
lsb_release -a
# Sollte "Debian GNU/Linux trixie/sid" oder ähnlich anzeigen
```

## Schritt 4: Python 3.9.23 Installation

### 4.1 Python-Installationsscript ausführen
```bash
cd openwb-trixie
chmod +x install_python3.9.sh
./install_python3.9.sh
```

**Was das Script macht:**
- Konfiguriert OpenWB-spezifische GPIO-Einstellungen in `/boot/firmware/config.txt`
- Deaktiviert Audio und vc4-kms-v3d
- Installiert alle notwendigen Build-Abhängigkeiten
- Kompiliert Python 3.9.23 aus dem Quellcode
- Führt Tests durch
- **Warnung**: Überschreibt die Standard-Python-Installation!
- Installiert `rpi-lgpio` für GPIO-Zugriff
- Konfiguriert PHP Upload-Limits auf 300M

### 4.2 Installation bestätigen
- Bestätige mit `y` wenn gefragt wird, ob die Standard-Python-Installation überschrieben werden soll
- **Nach der Python-Installation ist ein Neustart erforderlich** für die GPIO-Konfiguration!

```bash
sudo reboot
```

### 4.3 Python-Installation testen
```bash
python3 --version  # Sollte Python 3.9.23 anzeigen
python --version   # Sollte Python 3.9.23 anzeigen
pip3 --version
```

## Schritt 5: OpenWB Installation

### 5.1 OpenWB mit einer Zeile installieren
```bash
curl -s https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh | sudo bash
```

## Schritt 6: Finaler Neustart und Test

### 6.1 System neuzuuuu starten
```bash
sudo reboot
```

### 6.2 OpenWB-Dienste überprüfen
```bash
sudo systemctl status openwb
# Überprüfe ob alle OpenWB-Dienste laufen
```

### 6.3 Web-Interface testen
- Öffne in einem Browser: `http://[IP-DES-PI]`
- Das OpenWB Web-Interface sollte erscheinen

## One-Liner für Experten (nach Schritt 2)

Für erfahrene Nutzer - komplette Installation mit einem Befehl:
```bash
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_complete.sh | bash
```

## Wichtige Hinweise und Troubleshooting

### ⚠️ Wichtige Warnungen
- **Backup**: Erstelle vor jedem Schritt ein Backup deiner SD-Karte
- **Python-Installation**: Das Script überschreibt die Standard-Python-Installation - dies ist für OpenWB erforderlich
- **Neustarts**: Nach dem Trixie-Update und der Python-Installation sind Neustarts zwingend erforderlich

### 📋 Systemanforderungen
- Raspberry Pi 4 oder neuer (empfohlen)
- Mindestens 4GB RAM
- Schnelle SD-Karte (Class 10 oder besser)
- Stabile Internetverbindung für Downloads

### 🔧 Bei Problemen
- Überprüfe die Logs: `journalctl -u openwb`
- Python-Version prüfen: `python3 --version`
- GPIO-Konfiguration prüfen: `cat /boot/firmware/config.txt`
- Bei Fehlern: Backup-Dateien wiederherstellen

### 📁 Wichtige Dateipfade
- OpenWB-Installation: `/var/www/html/openWB/`
- GPIO-Konfiguration: `/boot/firmware/config.txt`
- PHP-Konfiguration: `/etc/php/8.4/apache2/conf.d/20-onfig.ini`
- Backup der Repository-Listen: `/etc/apt/sources.list.backup.*`

### 🔧 SSH-Verbindung mit PuTTY
1. Lade PuTTY herunter: https://www.putty.org/
2. Starte PuTTY
3. Gib die IP-Adresse des Raspberry Pi ein
4. Port: 22, Connection Type: SSH
5. Klicke auf "Open"
6. Login mit Benutzername `openwb` und deinem Passwort

Die Installation ist abgeschlossen, wenn das OpenWB Web-Interface erreichbar ist und alle Python-Module korrekt geladen werden.

## Zusammenfassung der Befehle

```bash
# Nach Raspberry Pi OS Installation und erstem Login:
sudo apt update && sudo apt upgrade -y
sudo reboot

# Trixie-Update
sudo apt install git -y
git clone https://github.com/Xerolux/openwb-trixie.git
cd openwb-trixie
chmod +x update_to_trixie.sh
./update_to_trixie.sh
sudo reboot

# Python 3.9.23 Installation
cd openwb-trixie
chmod +x install_python3.9.sh
./install_python3.9.sh
sudo reboot

# OpenWB Installation
curl -s https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh | sudo bash
sudo reboot
```
