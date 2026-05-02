# OpenWB Trixie Installer

Installiert OpenWB auf frischen Debian Trixie Systemen — mit whiptail-Menü, Feature-Patches und optionalen Tools.

## Schnellstart

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh)
```

> **Cache-Problem?** GitHub cached raw-Dateien aggressiv. Nutze den Commit-Hash:
> ```bash
> curl -fsSL "https://raw.githubusercontent.com/Xerolux/openwb-trixie/COMMIT/install.sh" -o /tmp/inst.sh && bash /tmp/inst.sh
> ```

## Menü

Beim Start erscheint ein whiptail-Menü mit 8 Optionen:

```
┌──────────────────────────────────────────────────────┐
│       OpenWB · Debian Trixie Installer               │
├──────────────────────────────────────────────────────┤
│                                                      │
│  [1] System-Python + venv       EMPFOHLEN            │
│      Python 3.13 · venv · ~10-15 Min                 │
│                                                      │
│  [2] Python 3.9.25 kompilieren  ORIGINAL             │
│      Ersetzt System-Python · ~30-60 Min              │
│                                                      │
│  [3] Python 3.14.4 + venv       NEUESTE              │
│      Zusatz-Installation · ~30-60 Min                │
│                                                      │
│  [4] Feature-Patches verwalten                       │
│                                                      │
│  [5] Legacy Wallbox Module  !!EXPERIMENTAL!!         │
│      go-e / KEBA / SimpleEVSE evcc-optimiert         │
│                                                      │
│  [6] Tools installieren                              │
│                                                      │
│  [7] Status anzeigen                                 │
│                                                      │
│  [8] Beenden                                         │
│                                                      │
└──────────────────────────────────────────────────────┘
```

Optionen 1–3 installieren OpenWB komplett (System-Update → Abhängigkeiten → Python → OpenWB → Patches).\
Optionen 4–6 sind nach der Installation verfügbar und kehren danach ins Menü zurück.

### Non-Interactive

```bash
# Ohne Menü, direkt installieren:
bash install.sh --venv              # Option 1
bash install.sh --python39          # Option 2
bash install.sh --python314         # Option 3
bash install.sh --non-interactive   # Option 1 automatisch
```

## Python-Optionen im Vergleich

| | Option 1: venv | Option 2: Python 3.9 | Option 3: Python 3.14 |
|---|---|---|---|
| **Flag** | `--venv` | `--python39` | `--python314` |
| **Dauer** | ~10-15 Min | ~30-60 Min | ~30-60 Min |
| **System-Python** | bleibt wie ist | wird ersetzt | bleibt wie ist |
| **Python-Version** | System (3.12/3.13) | 3.9.25 | 3.14.4 |
| **venv** | ja | nein | ja |
| **Code-Patches nötig** | ja | nein | ja |
| **Update-resistent** | ja | ja | ja |

**Empfehlung:** Option 1 (venv) — schnell, sauber, update-resistent.

## Feature-Patches

Update-sichere Patches die nach jedem OpenWB-Update automatisch reapplied werden.

| Patch | Beschreibung | Plattform |
|-------|-------------|-----------|
| **Sekundäre Wallboxen immer updaten** | Entfernt Branch-Prüfung beim Update sek. Wallboxen | Alle |
| **Kein Reboot nach Update** | Ersetzt `reboot` durch Service-Neustart | Alle |
| **Log-Rotation** | logrotate für OpenWB Logs (3 Tage, max 10MB) | Alle |
| **Swap einrichten** | Pi: rpi-swap (zram), andere: 2GB Swap-Datei | ARM |
| **SD-Kartenschutz** | tmpfs für /var/log, noatime, journald volatile | ARM |
| **Stromspar-Modus** | WiFi/BT/HDMI aus, CPU ondemand | Raspberry Pi |
| **Pi Beta-Repos** | Aktiviert RPi Beta/Test-Repositories | Raspberry Pi |

Patches werden über Menü-Option 4 verwaltet (installieren/entfernen).\
Aktivierte Patches werden in `/opt/openwb-patches/enabled.conf` gespeichert.

## Legacy Wallbox Module !!EXPERIMENTAL!!

> **WARNUNG:** Diese Module haben KEINERLEI offizielle Verbindung zu openWB!
> Inoffiziell, experimentell, **nie auf echter Hardware getestet**.
> Ausschliesslich auf eigene Gefar, kein Support, keine Haftung.
> Siehe [openwb_legacy_wallboxes_evcc_optimized/README.md](openwb_legacy_wallboxes_evcc_optimized/README.md).

Jede Wallbox kann einzeln installiert/entfernt werden (Menü-Option 5).
Aktivierte Module werden nach OpenWB-Updates automatisch reinstalliert.
Im Web-Interface erscheinen sie im Ladepunkt-Dropdown (Konfiguration als JSON).

| Modul | Protokoll | Features |
|-------|-----------|----------|
| **go-eCharger** | HTTP V1/V2 API | Auto-Erkennung, Phasenumschaltung (v2), RFID |
| **KEBA** | UDP Port 7090 | Reports 2/3/100, RFID-Autorisierung, Display |
| **SimpleEVSE WiFi** | HTTP API | setStatus/setCurrent, best-effort Phasen |

## Tools

Optionale Zusatz-Tools die als systemd-Services installiert werden.

| Tool | Beschreibung |
|------|-------------|
| **Modbus TCP Proxy** | Proxy für Modbus TCP Geräte, erlaubt mehreren Clients Zugriff |

Konfiguration nach der Installation unter `/etc/modbus-proxy/config.yaml`.

## Was das Script macht (Option 1–3)

1. System aktualisieren (`apt update && upgrade`)
2. Deutsche Standards (Zeitzone, Locale, Tastatur)
3. Abhängigkeiten installieren (Build-Tools, Apache, PHP, Mosquitto, etc.)
4. Repository klonen
5. GPIO konfigurieren (nur Raspberry Pi)
6. PHP konfigurieren (Upload-Limits 300M)
7. Python einrichten (je nach Option)
8. OpenWB installieren + Runtime-Patches + Post-Update Hook

### Update-Resistenz

Der Post-Update Hook (`post-update.sh`) patcht nach jedem OpenWB-Update automatisch:
- `atreboot.sh`: `pip3` → venv-pip (PEP 668 sicher)
- `openwb2.service`: venv-Python als ExecStart
- `simpleAPI.service`: venv-Python als ExecStart
- `requirements.txt`: jq/lxml/grpcio für Python 3.13+ angepasst
- `asyncio.coroutine` Shim für Python 3.11+
- Alle aktivierten Feature-Patches werden reapplied

## Unterstützte Plattformen

| Plattform | Status |
|-----------|--------|
| x86_64 (Proxmox, PC) | Funktioniert |
| ARM64 (RPi 4/5 64-bit) | Funktioniert |
| ARM32 (RPi 3/Zero 32-bit) | Funktioniert |
| Proxmox LXC/VM | Funktioniert |

Pi-spezifische Pakete und Patches werden automatisch nur auf echter Hardware angeboten.

## Voraussetzungen

- Frisches Debian Trixie
- SSH-Zugang
- Internetverbindung
- ~4 GB freier Speicherplatz

## Debian Trixie installieren

### Raspberry Pi

1. Raspberry Pi Imager → OS: Raspberry Pi OS (64-bit) Lite
2. Zahnrad: SSH aktivieren, Benutzer `openwb` anlegen
3. Auf SD-Karte schreiben, booten, SSH einloggen
4. Auf Trixie upgraden:
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo sed -i 's/bookworm/trixie/g' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null
   sudo apt update && sudo apt full-upgrade -y
   sudo reboot
   ```

### Direktes Image

1. Image von https://www.debian.org/devel/ laden
2. Auf SD-Karte/USB stick schreiben
3. Booten, Benutzer `openwb` anlegen

### Danach: Installer starten

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh)
```

## Wichtige Dateipfade

| Pfad | Beschreibung |
|------|-------------|
| `/var/www/html/openWB/` | OpenWB-Installation |
| `/opt/openwb-venv/` | Python Virtual Environment |
| `/opt/openwb-patches/` | Patch-Konfiguration (`enabled.conf`) |
| `/opt/openwb-tools/` | Tool-Konfiguration (`enabled.conf`) |
| `/home/openwb/openwb-trixie/` | Repository (Patches + Tools) |
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

**PEP 668 Fehler:**
```bash
# Post-Update Hook manuell ausführen:
sudo bash ~/openwb-trixie/openwb_post_update_hook.sh
```

**venv neu erstellen:**
```bash
sudo rm -rf /opt/openwb-venv
bash <(curl -fsSL https://raw.githubusercontent.com/Xerolux/openwb-trixie/main/install.sh) --venv
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
| `install.sh` | Haupt-Installer mit whiptail-Menü |
| `openwb_post_update_hook.sh` | Post-Update Hook (automatisch installiert) |
| `requirements.txt` | Python-Pakete fürs venv |
| `patches/` | Feature-Patches (modular, update-sicher) |
| `tools/` | Optionale Tools (modbus-proxy, etc.) |
| `openwb_legacy_wallboxes_evcc_optimized/` | Legacy Wallbox Module (experimentell) |

## Hinweis / Disclaimer

Dieses Projekt ist ein **inoffizielles, Community-basiertes Projekt** und steht in **keinerlei Verbindung** zum openWB-Projekt oder dessen Entwicklern.

**openWB** und alle damit verbundenen Marken, Logos und Software sind Eigentum der jeweiligen Rechteinhaber. Alle Rechte an der openWB-Software verbleiben beim openWB-Projekt (https://github.com/snaptec/openWB).

Dieses Repository stellt lediglich einen Installer und ergaenzende Module fuer den Betrieb von openWB auf Debian Trixie bereit. Es wird **keinerlei Gewaehrleistung, Support oder Haftung** uebernommen. Die Nutzung erfolgt **ausschliesslich auf eigene Gefahr**.

**openWB Projekt:** https://github.com/openWB/core

Siehe auch [LICENSE](LICENSE) (MIT).

