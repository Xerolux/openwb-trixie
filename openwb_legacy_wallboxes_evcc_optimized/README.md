# Legacy Wallbox Module — EXPERIMENTELL

> **WARNUNG: Diese Module haben KEINERLEI offizielle Verbindung zu openWB!**
>
> Es handelt sich um **inoffizielle, experimentelle Module** die von Grund auf
> neu geschrieben wurden. Sie sind **nicht** Teil des openWB-Projekts und werden
> **nicht** von den openWB-Entwicklern unterstützt.
>
> **Verwendung AUSSCHLIESSLICH auf eigene Gefahr!** Es gibt keinerlei Gewährleistung,
> Support oder Haftung — weder für Hardware, Software noch für daraus resultierende
> Schäden. Diese Module wurden **nie auf echter Hardware getestet** und dienen
> **ausschliesslich experimentellen Testzwecken**.

---

## Enthaltene Module

| Modul | Typ | Protokoll | Features |
|-------|-----|-----------|----------|
| **go-eCharger** (`legacy_goe_evcc`) | HTTP | V1 (`/status`) + V2 (`/api/status`) | Auto-API-Erkennung, Start/Stop (`frc`/`alw`), Strom (`amp`/`amx`), Phasenumschaltung (v2 `psm`), RFID (`trx`/`cards`), Leistung/Ströme/Spannung (`nrg`), Energie (`eto`), Fehlercodes |
| **KEBA** (`legacy_keba_evcc`) | UDP | Port 7090, Reports 2/3/100 | Start/Stop (`ena`), Strom (`curr`), RFID-Autorisierung (`start <rfid>`), Display, Leistung/Ströme/Spannung (Report 3), Energie (Report 3), Fehlercodes (Report 2) |
| **SimpleEVSE WiFi** (`legacy_simpleevse_evcc`) | HTTP | `/getParameters`, `/setCurrent`, `/setStatus` | Start/Stop (`setStatus`), Strom (`setCurrent`), Leistung (Firmware-abhängig), Ströme/Spannung (Firmware-abhängig), Energie (`meterReading`), RFID (best-effort) |

## Feature-Matrix

| Feature | go-e | KEBA UDP | SimpleEVSE WiFi |
|---|---:|---:|---:|
| Strom setzen | ja | ja | ja |
| Start/Stop | `frc`/`alw` | `ena` | `setStatus` |
| PV-Regelung | ueber openWB | ueber openWB | ueber openWB |
| Leistung | `nrg` | Report 3 | Firmware-abhaengig |
| Stroeme | `nrg` | Report 3 | Firmware-abhaengig |
| Spannung | `nrg` | Report 3 | Firmware-abhaengig |
| Energie | `eto` | Report 3 | `meterReading` |
| RFID | best-effort `trx/cards` | Report 100 / optional | best-effort |
| Phasenerkennung | ja | ja | best-effort |
| Phasenumschaltung | API v2 `psm` | nein/extern | nein/extern |
| CP-Unterbrechung | Stop-Fallback | Stop-Fallback | Stop-Fallback |

## Status: EXPERIMENTELL — NICHT GETESTET

- **Kein Hardware-Test:** Keines dieser Module wurde jemals auf echter
  Wallbox-Hardware getestet.
- **Kein Produktivbetrieb:** Diese Module sind **nicht** fuer den
  produktiven Einsatz geeignet.
- **Kein Support:** Es wird keinerlei Support geleistet. Nutzung
  ausschliesslich auf eigenes Risiko.
- **Keine evcc-Kopie:** Die Module wurden orientiert an evcc-Verhalten
  neu geschrieben, enthalten aber keinen evcc-Code.

## Installation

Der openWB Trixie Installer bietet einen eigenen Menuepunkt **"Legacy Wallbox Module"**
an. Jede Wallbox kann einzeln installiert oder entfernt werden.

Nach OpenWB-Updates werden aktivierte Module automatisch reinstalliert.

Manuell: Den Ordner `packages/modules/chargepoints/*` in den openWB-core-Checkout
kopieren und openWB neu starten (`sudo systemctl restart openwb2`).

## Abgleich mit evcc

- **go-e:** evcc nutzt lokale V1/V2-Erkennung, V2 `/api/status`, V1 `/status`,
  Start/Stop ueber `frc`/`alw`, Strom ueber `amp`/`amx`, Phasenwechsel V2 ueber `psm`.
- **KEBA:** evcc nutzt UDP `ena`, `curr`, `start <rfid>` und Reports 2, 3, 100.
- **SimpleEVSE:** In evcc wurde kein identisches SimpleEVSE-WiFi-HTTP-Modul gefunden.
  SimpleEVSE bleibt am openWB-1.9-HTTP-Verhalten orientiert.

## Phasenumschaltung

- **go-e:** API v2 per `psm` (1=1p, 2=3p)
- **KEBA/SimpleEVSE:** Keine native Umschaltung — extern per IO/Schuetz noetig

## Haftungsausschluss

DIESE SOFTWARE WIRD "WIE BESEHEN" BEREITGESTELLT, OHNE JEGLICHE GEWAEHRLEISTUNG.
DIES SCHLIESST ABER NICHT BESCHRAENKT AUF DIE STILLSCHWEIGENDE GEWAEHRLEISTUNG
DER MARKTREIFE ODER DER EIGNUNG FUER EINEN BESTIMMTEN ZWECK EIN.
IN KEINEM FALL SIND DIE AUTOREN ODER COPYRIGHT-INHABER FUER IRGENDWELCHE ANSPRUECHE,
SCHAEDEN ODER ANDERE HAFTUNGEN VERANTWORTLICH, SEIEN SIE AUS VERTRAG, UNERLAUBTER
HANDLUNG ODER ANDERWEITIG ENTSTANDEN, IN VERBINDUNG MIT DER SOFTWARE ODER DER
NUTZUNG ODER DEM SONSTIGEN UMGANG MIT DER SOFTWARE.
