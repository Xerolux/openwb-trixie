# OpenWB auf Debian Trixie Installation - Komplette Anleitung

## 🚀 Schnellstart

### Für frische Trixie-Installation (EMPFOHLEN - spart 30-60 Min!)

**One-Liner für Debian Trixie (nutzt System-Python, keine Kompilierung!):**
```bash
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_trixie_direct.sh | bash
```

**Was passiert:**
- ✓ Nutzt System-Python (3.12+) - KEINE Kompilierung!
- ✓ Erstellt isoliertes venv in `/opt/openwb-venv`
- ✓ Überlebt OpenWB-Updates automatisch
- ✓ Installation in ~10-15 Minuten (statt 60-90 Min!)

### Für Bookworm -> Trixie Upgrade

Falls du von Bookworm upgraden willst, folge der [vollständigen Anleitung unten](#schritt-1-raspberry-pi-os-bookworm-light-64-bit-installieren).

---

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

## Schritt 4: Python Installation

### 4.1 Wähle Installationsmethode

**🎯 NEU & EMPFOHLEN: Virtual Environment mit System-Python (schnell!)**

Nutzt das System-Python von Trixie - KEINE Kompilierung nötig!
```bash
cd openwb-trixie
chmod +x install_python3.9.sh
./install_python3.9.sh --with-venv  # oder --venv-only
```

**Vorteile:**
- ✅ **Keine Python-Kompilierung** (spart 30-60 Minuten!)
- ✅ Nutzt modernes **Debian Trixie Python 3.12+**
- ✅ **Isolierte Paket-Installation** (venv)
- ✅ **Überlebt OpenWB-Updates** automatisch
- ✅ Post-Update Hook wird automatisch installiert

**Legacy: Python 3.9.23 kompilieren (nur für Kompatibilität)**
```bash
cd openwb-trixie
chmod +x install_python3.9.sh
./install_python3.9.sh  # ohne Flag
```

⚠️ **Warnung:** Überschreibt System-Python und dauert 30-60 Minuten!

### 4.2 Was das Script macht

**Mit --with-venv oder --venv-only (EMPFOHLEN):**
- Konfiguriert OpenWB-spezifische GPIO-Einstellungen
- Deaktiviert Audio und vc4-kms-v3d
- Erstellt venv in `/opt/openwb-venv` mit System-Python
- Installiert alle Pakete aus `requirements.txt`
- Erstellt Wrapper-Skript `openwb-activate`
- Installiert Post-Update Hook automatisch
- **KEINE Python-Kompilierung!** ⚡

**Legacy-Modus (ohne Flags):**
- Alle oben genannten Konfigurationen
- + Kompiliert Python 3.9.23 aus Quellcode (30-60 Min!)
- + Überschreibt System-Python
- + Führt Tests durch

### 4.3 Installation

**Mit venv (empfohlen):**
- Keine Bestätigung nötig
- Kein Neustart erforderlich (nur GPIO-Config wird geändert)
- Schnelle Installation in ~2-5 Minuten

**Legacy-Modus:**
- Bestätige mit `y` wenn gefragt
- **Neustart erforderlich** nach Installation
- Installation dauert 30-60 Minuten

```bash
sudo reboot  # Nur bei Legacy-Modus nötig
```

### 4.4 Python-Installation testen
```bash
python3 --version  # Sollte Python 3.9.23 anzeigen
python --version   # Sollte Python 3.9.23 anzeigen
pip3 --version
```

### 4.5 Virtual Environment verwenden (nur bei --with-venv)

**Manuell aktivieren:**
```bash
source /opt/openwb-venv/bin/activate
python script.py
deactivate
```

**Mit Wrapper (einfacher):**
```bash
openwb-activate python script.py
```

**In systemd Services:**
```ini
[Service]
EnvironmentFile=/opt/openwb-venv/systemd-environment
ExecStart=/opt/openwb-venv/bin/python /path/to/script.py
```

## Schritt 5: OpenWB Installation

### 5.1 OpenWB mit einer Zeile installieren
```bash
curl -s https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh | sudo bash
```

## Schritt 6: Finaler Neustart und Test

### 6.1 System neu starten
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

## One-Liner für Experten

### 🚀 Für frische Trixie-Installation (SCHNELLSTE Option!)

**Nutzt System-Python, keine Kompilierung (~10-15 Min):**
```bash
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_trixie_direct.sh | bash
```

### Für Bookworm -> Trixie Upgrade

**Mit venv (empfohlen, ~40-50 Min):**
```bash
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_complete.sh | bash -s -- --with-venv
```

**Legacy ohne venv (~60-90 Min):**
```bash
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_complete.sh | bash
```

## Virtual Environment Wartung

### 🔄 venv nach OpenWB-Updates aktualisieren

**✨ NEU: Komplett automatisch!**

Bei Installation mit `--with-venv` oder `--venv-only` wird der Post-Update Hook **automatisch installiert**. Das venv wird nach jedem OpenWB-Update automatisch aktualisiert - **kein manuelles Eingreifen nötig!**

**Manuelle Aktualisierung (falls nötig):**
```bash
cd openwb-trixie
./install_python3.9.sh --venv-only
# oder
./setup_venv.sh --update
```

**Post-Update Hook manuell prüfen:**
```bash
# Prüfe ob Hook installiert ist
ls -la /var/www/html/openWB/data/config/post-update.sh

# Hook manuell installieren (nur falls nötig)
sudo cp openwb_post_update_hook.sh /var/www/html/openWB/data/config/post-update.sh
sudo chmod +x /var/www/html/openWB/data/config/post-update.sh
```

### 📦 Neue Pakete hinzufügen

**Zur requirements.txt hinzufügen:**
```bash
# Bearbeite requirements.txt
nano openwb-trixie/requirements.txt

# Füge dein Paket hinzu, z.B.:
# requests>=2.31.0

# Aktualisiere das venv
./setup_venv.sh --update
```

**Direkt ins venv installieren:**
```bash
openwb-activate pip install paketname
# oder
source /opt/openwb-venv/bin/activate
pip install paketname
pip freeze > /opt/openwb-venv/installed_requirements.txt
deactivate
```

### 🔍 venv-Status prüfen

```bash
# Installierte Pakete anzeigen
openwb-activate pip list

# Python-Version im venv
openwb-activate python --version

# venv-Konfiguration anzeigen
cat /opt/openwb-venv/.openwb-venv-config
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

**Allgemein:**
- Überprüfe die Logs: `journalctl -u openwb`
- Python-Version prüfen: `python3 --version`
- GPIO-Konfiguration prüfen: `cat /boot/firmware/config.txt`
- Bei Fehlern: Backup-Dateien wiederherstellen

**venv-spezifisch:**
- **venv existiert nicht**: Führe `./install_python3.9.sh --venv-only` aus
- **Paket-Fehler**: Aktualisiere mit `./setup_venv.sh --update`
- **openwb-activate nicht gefunden**: Prüfe `/usr/local/bin/openwb-activate`
- **Berechtigungsfehler**: `sudo chown -R openwb:openwb /opt/openwb-venv`
- **venv neu erstellen**:
  ```bash
  sudo rm -rf /opt/openwb-venv
  ./setup_venv.sh
  ```

### 📁 Wichtige Dateipfade
- OpenWB-Installation: `/var/www/html/openWB/`
- Virtual Environment: `/opt/openwb-venv/`
- venv Wrapper: `/usr/local/bin/openwb-activate`
- venv Config: `/opt/openwb-venv/.openwb-venv-config`
- Requirements: `/home/openwb/openwb-trixie/requirements.txt`
- Post-Update Hook: `/var/www/html/openWB/data/config/post-update.sh`
- GPIO-Konfiguration: `/boot/firmware/config.txt`
- PHP-Konfiguration: `/etc/php/8.4/apache2/conf.d/20-uploadlimit.ini`
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

### 🚀 Methode 1: Direkt auf Trixie (SCHNELLSTE Option!)

**Nutzt System-Python, keine Kompilierung (~10-15 Min):**
```bash
# Voraussetzung: Debian Trixie bereits installiert
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_trixie_direct.sh | bash
```

**Oder manuell:**
```bash
# System auf Trixie upgraden (falls noch Bookworm)
sudo apt install git -y
git clone https://github.com/Xerolux/openwb-trixie.git
cd openwb-trixie
chmod +x update_to_trixie.sh
./update_to_trixie.sh
sudo reboot

# venv mit System-Python erstellen (KEINE Kompilierung!)
cd openwb-trixie
chmod +x install_python3.9.sh
./install_python3.9.sh --venv-only

# OpenWB Installation
curl -s https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh | sudo bash
sudo reboot
```

### Methode 2: Bookworm -> Trixie mit venv (empfohlen)

**Mit automatischem Post-Update Hook (~40-50 Min):**
```bash
# Nach Raspberry Pi OS Bookworm Installation:
sudo apt update && sudo apt upgrade -y
sudo reboot

# Komplette Installation mit venv (nutzt System-Python)
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install_complete.sh | bash -s -- --with-venv
```

**Oder manuell:**
```bash
# Trixie-Update
sudo apt install git -y
git clone https://github.com/Xerolux/openwb-trixie.git
cd openwb-trixie
chmod +x update_to_trixie.sh
./update_to_trixie.sh
sudo reboot

# venv Setup (nutzt System-Python, KEINE Kompilierung!)
cd openwb-trixie
chmod +x install_python3.9.sh
./install_python3.9.sh --venv-only
# Post-Update Hook wird automatisch installiert!

# OpenWB Installation
curl -s https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh | sudo bash
sudo reboot
```

### Methode 3: Legacy mit Python 3.9.23 Kompilierung

**Nur für spezielle Kompatibilitätsanforderungen (~60-90 Min):**
```bash
# Nach Raspberry Pi OS Installation:
sudo apt update && sudo apt upgrade -y
sudo reboot

# Trixie-Update
sudo apt install git -y
git clone https://github.com/Xerolux/openwb-trixie.git
cd openwb-trixie
chmod +x update_to_trixie.sh
./update_to_trixie.sh
sudo reboot

# Python 3.9.23 kompilieren (dauert 30-60 Min!)
cd openwb-trixie
chmod +x install_python3.9.sh
./install_python3.9.sh  # ohne Flag
sudo reboot

# OpenWB Installation
curl -s https://raw.githubusercontent.com/openWB/core/master/openwb-install.sh | sudo bash
sudo reboot
```

### Nur venv erstellen/aktualisieren

**Wenn System bereits Trixie ist:**
```bash
cd openwb-trixie
./install_python3.9.sh --venv-only

# Oder direkt:
./setup_venv.sh

# Aktualisieren:
./setup_venv.sh --update
```

## Skript-Referenz

Alle Skripte unterstützen `--help` für detaillierte Informationen.

### install_trixie_direct.sh
**Schnellste Option für frische Trixie-Systeme**
```bash
./install_trixie_direct.sh [--help]
```
- Für Systeme die **bereits Debian Trixie** verwenden
- Nutzt System-Python mit venv (keine Kompilierung)
- Installation in ~10-15 Minuten
- Installiert automatisch: GPIO-Config, PHP-Limits, venv, OpenWB, Post-Update Hook

### install_complete.sh
**Komplette Installation mit Trixie-Upgrade**
```bash
./install_complete.sh [--with-venv] [--help]
```
| Option | Beschreibung |
|--------|--------------|
| (keine) | Legacy: Kompiliert Python 3.9.23 (~60-90 Min) |
| --with-venv | Modern: Nutzt System-Python + venv (~40-50 Min) |
| --help | Zeigt Hilfe |

- Automatische Neustarts und Fortsetzung
- Für Bookworm → Trixie Upgrade

### install_python3.9.sh
**Python Installation und venv Setup**
```bash
./install_python3.9.sh [--with-venv|--venv-only] [--help]
```
| Option | Beschreibung |
|--------|--------------|
| (keine) | Legacy: Kompiliert Python 3.9.23 (30-60 Min) |
| --with-venv | GPIO-Config + venv mit System-Python |
| --venv-only | Nur venv erstellen/aktualisieren |
| --help | Zeigt Hilfe |

### update_to_trixie.sh
**Debian Bookworm → Trixie Upgrade**
```bash
./update_to_trixie.sh [--help]
```
- Erstellt Backups der sources.list
- Führt `apt full-upgrade` durch
- Neustart erforderlich nach Abschluss

### setup_venv.sh
**Virtual Environment Verwaltung**
```bash
./setup_venv.sh [--update] [--help]
```
| Option | Beschreibung |
|--------|--------------|
| (keine) | Erstellt neues venv |
| --update | Aktualisiert bestehendes venv |
| --help | Zeigt Hilfe |

- Erstellt venv in `/opt/openwb-venv`
- Installiert Pakete aus `requirements.txt`
- Erstellt Wrapper `openwb-activate`

### openwb_post_update_hook.sh
**Automatische venv-Updates nach OpenWB-Updates**
```bash
./openwb_post_update_hook.sh [--help]
```
- Wird automatisch nach OpenWB-Updates ausgeführt
- Aktualisiert Python-Pakete im venv
- Installation: Kopieren nach `/var/www/html/openWB/data/config/post-update.sh`
