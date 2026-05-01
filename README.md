# OpenWB auf Debian Trixie

Ein Installer für OpenWB auf frischen Debian Trixie Systemen.

## Schnellstart

```bash
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh | bash
```

Das Script zeigt ein Menü mit drei Python-Optionen. Alternativ direkt:

```bash
# Option 1: System-Python + venv (empfohlen, ~10-15 Min)
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh | bash -s -- --venv

# Option 2: Python 3.9.25 kompilieren (~30-60 Min)
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh | bash -s -- --python39

# Option 3: Python 3.14.4 kompilieren + venv (~30-60 Min)
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh | bash -s -- --python314
```

## Voraussetzungen

- Frisches Debian Trixie (kein Bookworm-Upgrade!)
- SSH-Zugang
- Internetverbindung
- ~4 GB freier Speicherplatz

## Die drei Python-Optionen

Beim Start erscheint folgendes Menü:

```
  ┌─────────────────────────────────────────────────────────┐
  │              Python-Installationsmodus wählen           │
  ├─────────────────────────────────────────────────────────┤
  │                                                         │
  │   [1]  System-Python + venv              EMPFOHLEN      │
  │        Aktuelles System-Python (3.13.5)                 │
  │        Pakete isoliert im Virtual Environment           │
  │        System bleibt unangetastet                       │
  │        Dauer: ca. 10-15 Minuten                         │
  │                                                         │
  │   [2]  Python 3.9.25 kompilieren         ORIGINAL       │
  │        Kompiliert aus Quellcode, ersetzt System-Python  │
  │        Keine Anpassungen am OpenWB-Code nötig           │
  │        Dauer: ca. 30-60 Minuten                         │
  │                                                         │
  │   [3]  Python 3.14.4 kompilieren + venv  NEUSTE         │
  │        Kompiliert neuestes Python als Zusatz-Install.   │
  │        System-Python bleibt unverändert                 │
  │        venv nutzt das neu kompilierte Python 3.14       │
  │        Dauer: ca. 30-60 Minuten                         │
  │                                                         │
  └─────────────────────────────────────────────────────────┘
```

### Vergleich

| | Option 1: venv | Option 2: Python 3.9 | Option 3: Python 3.14 |
|---|---|---|---|
| **Flag** | `--venv` | `--python39` | `--python314` |
| **Dauer** | ~10-15 Min | ~30-60 Min | ~30-60 Min |
| **System-Python** | bleibt wie ist | wird ersetzt | bleibt wie ist |
| **Python-Version** | System (3.12/3.13/3.14) | 3.9.25 | 3.14.4 |
| **venv** | ja | nein | ja |
| **Code-Patches nötig** | ja | nein | ja |
| **Update-resistent** | ja (Post-Update Hook) | ja | ja (Post-Update Hook) |
| **Empfohlen für** | Standard | Original-Getreue | Neuestes Python |

### Empfehlung

- **Option 1** ist die beste Wahl für die meisten Nutzer. Schnell, sauber, update-resistent.
- **Option 2** nur wenn man exakt das Original-OpenWB-Verhalten ohne jegliche Patches will.
- **Option 3** für Nutzer die das neueste Python wollen, ohne das System zu verändern.

## Unterstützte Plattformen

| Plattform | Getestet | Status |
|-----------|----------|--------|
| x86_64 (Proxmox, PC) | ja | Funktioniert |
| ARM64 (RPi 4/5 64-bit) | ja | Funktioniert |
| ARM32 (RPi 3/Zero 32-bit) | Logik geprüft | Funktioniert |
| Proxmox LXC/VM | ja | Funktioniert |

GPIO/Raspberry-Pi-spezifische Pakete werden automatisch nur auf echter Hardware installiert.

## Was das Script macht

1. System aktualisieren
2. Deutsche Standards setzen (Zeitzone/Locale/Tastatur)
3. Abhängigkeiten installieren
4. Repository klonen
5. GPIO konfigurieren (nur Raspberry Pi)
6. PHP konfigurieren (Upload-Limits)
7. Python einrichten (je nach gewählter Option)
8. OpenWB installieren + Runtime-Patches + Post-Update Hook

### Update-Resistenz

Nach jedem OpenWB-Update startet der Post-Update Hook automatisch und patcht:
- `atreboot.sh`: Alle `pip3` Aufrufe auf venv-pip umgeleitet (PEP 668 sicher)
- `openwb2.service`: venv-Python als ExecStart
- `simpleAPI.service`: venv-Python als ExecStart
- `requirements.txt`: jq/lxml/grpcio für Python 3.13+ angepasst
- `asyncio.coroutine` Kompatibilitäts-Shim für Python 3.11+

## Debian Trixie installieren

### Variante A: Raspberry Pi Imager

1. Raspberry Pi Imager herunterladen
2. OS wählen: Raspberry Pi OS (64-bit) Lite
3. Zahnrad: SSH aktivieren, Benutzer `openwb` anlegen
4. Auf SD-Karte schreiben, booten, per SSH einloggen
5. Auf Trixie upgraden:
   ```bash
   sudo apt update && sudo apt upgrade -y
   # sources.list von bookworm auf trixie ändern
   sudo sed -i 's/bookworm/trixie/g' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null
   sudo apt update && sudo apt full-upgrade -y
   sudo reboot
   ```

### Variante B: Direktes Debian Trixie Image

1. Image von https://www.debian.org/devel/ herunterladen
2. Auf SD-Karte/USB stick schreiben
3. Booten, SSH einrichten, Benutzer `openwb` anlegen

### Danach: Installer ausführen

```bash
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh | bash
```

## Wichtige Dateipfade

| Pfad | Beschreibung |
|------|-------------|
| `/var/www/html/openWB/` | OpenWB-Installation |
| `/opt/openwb-venv/` | Virtual Environment (Option 1 & 3) |
| `/opt/python3.14.4/` | Kompiliertes Python (nur Option 3) |
| `/usr/local/bin/openwb-activate` | venv Wrapper |
| `/var/www/html/openWB/ramdisk/` | Laufzeit-Logs |
| `/var/www/html/openWB/data/config/post-update.sh` | Post-Update Hook |

## Troubleshooting

### Schnelldiagnose

```bash
sudo systemctl status openwb2 --no-pager
journalctl -u openwb2 -n 50 --no-pager
cat /var/www/html/openWB/ramdisk/thread_errors.log
```

### Häufige Probleme

**Web-Interface hängt bei "Systemstart noch nicht abgeschlossen":**
```bash
sudo systemctl restart openwb2
```

**PEP 668 Fehler (`externally-managed-environment`):**
```bash
# Nur bei Option 1 & 3 nötig - sollte automatisch gepatcht sein
cd ~/openwb-trixie && sudo bash openwb_post_update_hook.sh
```

**asyncio.coroutine Fehler:**
```bash
# Shim sollte automatisch installiert sein
ls /opt/openwb-venv/lib/python*/site-packages/openwb_py313_compat.py
```

**venv neu erstellen:**
```bash
sudo rm -rf /opt/openwb-venv
cd ~/openwb-trixie
curl -s https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh | bash -s -- --venv
```

**Services neustarten:**
```bash
sudo systemctl restart mosquitto mosquitto_local openwb2 openwb-simpleAPI
```

## Kommandozeilen-Optionen

```
./install.sh [OPTION]

Optionen:
  --venv, -v          System-Python + venv (Option 1)
  --python39, -l      Python 3.9.25 kompilieren (Option 2)
  --python314, -p     Python 3.14.4 kompilieren + venv (Option 3)
  --non-interactive   Keine Rückfragen (wählt Option 1)
  --help, -h          Hilfe anzeigen
```

## Dateien im Repository

| Datei | Beschreibung |
|-------|-------------|
| `install.sh` | Haupt-Installer (dieses Script macht alles) |
| `openwb_post_update_hook.sh` | Post-Update Hook (wird automatisch installiert) |
| `requirements.txt` | Python-Pakete fürs venv |
| `setup_venv.sh` | venv Setup (wird vom Installer aufgerufen) |
| `install_python3.9.sh` | Python 3.9 Legacy-Installer (einzeln nutzbar) |
| `install_trixie_direct.sh` | Direkt-Installer mit venv (einzeln nutzbar) |
| `install_complete.sh` | Komplett-Installer mit Bookworm-Upgrade (einzeln nutzbar) |
| `update_to_trixie.sh` | Bookworm auf Trixie upgraden (einzeln nutzbar) |
