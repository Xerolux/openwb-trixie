# openWB Trixie / Python 3.13+ Support

**Branch:** `feature/trixie-python313-support` auf [Xerolux/core](https://github.com/Xerolux/core/tree/feature/trixie-python313-support)
**Server:** 192.168.178.32 (Debian Trixie 13.4, Python 3.13.5, KVM/AMD x86_64)
**Status:** **Getestet und laeuft live — Full-Install ab nacktem Debian**

---

## Zusammenfassung

Vollstaendige Migration von openWB auf Debian Trixie (13) mit Python 3.13+.
Enthaelt alle Dependency-Upgrades + Platform Detection + venv + NTP + MOTD.

### Branch enthaelt 6 Commits

```
312fee5d9 Fix MOTD: use printf with ANSI codes instead of tput
d4d8dab40 Add chrony NTP and login MOTD
b6bee15c1 Add Debian Trixie / Python 3.13+ support with platform detection
57ed59049 Upgrade ocpp 1.0 to 2.1.0 and websockets 12.0 to 16.0
7d9b0ebda Upgrade paho-mqtt 1.6.1 to 2.1.0
651c7c30b Upgrade pymodbus 2.5.2 to 3.x
```

---

## 1. Platform Detection (`runs/platform_detect.sh`)

Neues Shell-Modul das erkennt:
- **Architektur:** x86_64, aarch64, armhf
- **Debian Version + Codename:** automatisch aus `/etc/os-release`
- **Virtualisierung:** KVM, VMware, LXC, Container, none (via `systemd-detect-virt`)
- **Raspberry Pi:** via `/proc/device-tree/model`
- **64-bit:** ja/nein

Stellt Funktionen bereit:
- `platform_has_gui` — ob GUI-Pakete (chromium, lightdm) installiert werden sollen
- `platform_install_gui_packages` — installiert GUI nur auf RPi oder Bare Metal
- `platform_install_rpi_packages` — installiert gpiozero nur auf RPi
- `ensure_venv` — erstellt `/opt/openwb-venv` falls nicht vorhanden
- `venv_pip` — fuehrt pip im venv aus

---

## 2. Virtual Environment (`/opt/openwb-venv`)

### Warum?
- Debian Trixie hat PEP 668 — `pip install` in System-Python ist blockiert
- venv isoliert openWB-Pakete vom System
- Erlaubt beliebige Python-Version im venv unabhaengig vom OS

### Aenderungen
- `openwb-install.sh`: Erstellt venv, installiert Requirements dort
- `atreboot.sh`: `ensure_venv()` + venv pip fuer Requirements
- Alle 3 Service-Files: `ExecStart=/opt/openwb-venv/bin/python3 ...`
- Service-Versionen erhoeht (openwb2: 4→5, simpleAPI: 1→2, remoteSupport: 3→4)

---

## 3. Platform-Aware Paketinstallation (`runs/install_packages.sh`)

### Entfernt (Trixie-Probleme)
- `python3-pip` — PEP 668 Konflikt (pip kommt jetzt via venv)
- `python3-urllib3` — Konflikt mit pip-managed urllib3
- `mmc-utils` — nur auf RPi (jetzt konditional)

### Hinzugefuegt
- `python3-venv` — fuer Virtual Environment
- `python3-dev` — fuer C-Extensions (lxml, cryptography, etc.)
- `chrony` — NTP Zeitsynchronisation

### Konditional
- GUI-Pakete (chromium, lightdm, etc.) — nur auf RPi oder Bare Metal
- `gpiozero` — nur auf RPi
- `evdev` — nur wenn Platform-kompatibel (im venv)

---

## 4. Chrony NTP (`data/config/chrony/chrony.conf`)

Ersetzt `systemd-timesyncd` durch chrony mit:
- **PTB Braunschweig** ( Deutschland): `ptbtime1.ptb.de` (prefer), `ptbtime2.ptb.de`
- **NTP Pool Deutschland**: `0.de.pool.ntp.org`
- **Ubuntu NTP Pools** (Zuverlaessig): `ntp.ubuntu.com` + regionale Pools
- Erlaubt Anfragen aus lokalem Netzwerk (fuer LAN-Ladepunkte)
- Automatische RTC-Synchronisation

### Integration
- `install_packages.sh`: chrony in COMMON_PACKAGES
- `atreboot.sh`: stoppt systemd-timesyncd, konfiguriert chrony (versionMatch)
- `openwb-install.sh`: gleiches Setup

---

## 5. MOTD (`data/config/profile.d/99-openwb-motd.sh`)

Login-Message die zeigt:
```
╔══════════════════════════════════════════════════════════╗
║                    openWB 2.0                            ║
╚══════════════════════════════════════════════════════════╝
  Web UI:      http://192.168.178.32/openWB/
  Status:      active
  Git:         feature/trixie-python313-support @ d4d8dab40
  OS:          Debian GNU/Linux 13 (trixie)
  Uptime:      up 7 minutes
  Load:        1.05 0.68 0.32
  Memory:      417Mi/1.9Gi

  Logs: journalctl -u openwb2 -f
```

- Farbig (gruen=active, rot=failed) bei Terminal, plain bei non-TTY
- Wird bei jedem SSH-Login angezeigt
- Via `atreboot.sh` und `openwb-install.sh` nach `/etc/profile.d/` installiert

---

## 6. Bugfixes fuer Python 3.13+

### datetime.utcnow() / utcfromtimestamp() (deprecated 3.12+)
- `packages/modules/vehicles/vwgroup/vwgroup.py`
- `packages/modules/vehicles/tronity/api.py`
- `packages/modules/vehicles/ovms/api.py`

### Shebangs
- 2x `#!/usr/bin/python` → `#!/usr/bin/env python3`

### vcgencmd
- `packages/helpermodules/create_debug.py`: vcgencmd jetzt mit try/except (nicht-RPi)

### requirements.txt
- `asyncio>=4.0.0` entfernt (stdlib-shim nicht noetig auf Python 3.13)
- `evdev>=1.9.3` auskommentiert (platform-spezifisch, wird separat installiert)

---

## 7. PHP Upload-Limit

`openwb-install.sh` erkennt jetzt **automatisch** die PHP-Version:
- Alt: hardcoded `/etc/php/7.3/` und `/etc/php/7.4/`
- Neu: scannt `/etc/php/*/apache2/conf.d/` — funktioniert mit PHP 8.2+ (Trixie)

---

## 8. CI Workflow

- Python 3.9 → **Matrix: 3.10, 3.12, 3.13**
- Testet gegen alle supported Python-Versionen

---

## Server-Test Ergebnis

```
● openwb2.service - "Regelung openWB 2.0"
     Active: active (running)
     Main PID: /opt/openwb-venv/bin/python3 /var/www/html/openWB/packages/main.py

Chrony: active, synced to ptbtime1.ptb.de (Stratum 2)
Web UI: HTTP 200
MOTD:   working
```

## Bekannte Blocker fuer openWB/core

- **pymodbus 3.13.0 erfordert Python >=3.10** — openWB Core setzt aktuell Python 3.9 ein
- **atreboot.sh Watchdog** — der interne 900s Watchdog killt den Prozess in manchen Faellen
- **mosquitto_local** — braucht ein installiertes init.d Script (fehlt bei nacktem Debian)
