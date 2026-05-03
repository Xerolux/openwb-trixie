# openWB Dependency Upgrade 2025

**Datum:** 2026-05-03
**Branch:** `feature/deps-upgrade-2025` auf [Xerulux/core](https://github.com/Xerolux/core/tree/feature/deps-upgrade-2025)
**Server:** 192.168.178.32 (Debian Trixie 13.4, Python 3.13.5)
**Status:** **Getestet und laeuft live**

---

## Zusammenfassung

Alle 26 Python-Pakete in `requirements.txt` wurden auf die neuesten Versionen (Stand Mai 2025) aktualisiert. Drei Pakete erforderten Code-Aenderungen:

| Package | Alte Version | Neue Version | Code-Aenderungen | Dateien |
|---------|-------------|-------------|-----------------|---------|
| **pymodbus** | 2.5.2 | 3.13.0 | API-Komplettumbau | 164 |
| **paho-mqtt** | 1.6.1 | 2.1.0 | Neues CallbackAPIVersion-Arg | 8 |
| **ocpp** | 1.0.0 | 2.1.0 | cp.call() Response statt ws.messages | 1 |
| **websockets** | 12.0 | 16.0 | InvalidStatus statt InvalidStatusCode | (gleiche Datei) |

Alle uebrigen 22 Pakete waren Drop-in-Upgrades ohne Code-Aenderungen.

---

## 1. pymodbus 2.5.2 → 3.13.0

**Komplette API-Aenderung.** 164 Dateien mussten angepasst werden.

### Wesentliche Aenderungen
- `pymodbus.client.sync` → `pymodbus.client` (Modul umbenannt)
- `ModbusSocketFramer` → `FramerType.SOCKET` (Enum statt Klasse)
- `unit=` → `device_id=` (Parameter umbenannt)
- `response.getRegister(i)` → `response.registers[i]`
- `Endian` und `BinaryPayloadBuilder/Decoder` entfernt → lokaler Compat-Shim
- `count` und `device_id` sind jetzt keyword-only
- `port` bei `ModbusSerialClient` ist positional-only

### Compat-Shim (`pymodbus_compat.py`)
Neue Datei `packages/modules/common/pymodbus_compat.py` mit:
- `Endian` (Big/Little Enum)
- `BinaryPayloadBuilder` (struct-basiert)
- `BinaryPayloadDecoder` (struct-basiert)

### Minimum-Python
`pymodbus>=3.13.0` erfordert **Python >=3.10** — nicht kompatibel mit Python 3.9.

### Bereits als PR eingereicht
https://github.com/openWB/core/pull/3340

---

## 2. paho-mqtt 1.6.1 → 2.1.0

**Breaking Change:** `mqtt.Client()` erfordert jetzt `CallbackAPIVersion` als erstes Argument.

### Migration
```python
# Alt:
client = mqtt.Client("id")
client = mqtt.Client()

# Neu:
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id="id")
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
```

### Betroffene Dateien (8)
- `packages/helpermodules/broker.py`
- `packages/modules/smarthome/mqtt/{off,on,watt}.py`
- `packages/smarthome/smartcommon.py`
- `runs/remoteSupport/remoteSupport.py`
- `simpleAPI/simpleAPI_mqtt.py`
- `requirements.txt`

### Minimum-Python
`paho-mqtt>=2.1.0` erfordert **Python >=3.7** — kompatibel mit Python 3.9.

---

## 3. ocpp 1.0.0 → 2.1.0 + websockets 12.0 → 16.0

**Nur 1 Datei betroffen:** `packages/control/ocpp.py`

### Aenderungen
- **`ws.messages[0]` entfernt:** In websockets 16 gibt es kein `.messages` mehr auf WebSocket-Verbindungen.
  - Loesung: `cp.call()` gibt direkt das Response-Payload zurueck (z.B. `response.transaction_id`)
- **`response = None` vor try:** Verhindert UnboundLocalError bei TimeoutError
- **`InvalidStatusCode` → `InvalidStatus`:** Deprecated in websockets 16
- **`WebSocketClientProtocol` type hint entfernt:** Deprecated in websockets 16
- **`import json` entfernt:** Wird nicht mehr benoetigt

### Vorher
```python
ws = self._process_call(...)
if ws:
    transaction_id = json.loads(ws.messages[0])[2]["transactionId"]
```

### Nachher
```python
result = self._process_call(...)
if result:
    _ws, response = result
    if response is None:
        return None
    transaction_id = response.transaction_id
```

---

## 4. Alle anderen Pakete (Drop-in Upgrades)

| Package | Alt | Neu |
|---------|-----|-----|
| typing-extensions | 4.13.2 | >=4.15.0 |
| jq | 1.1.3 | >=1.11.0 |
| pytest | 6.2.5 | >=9.0.3 |
| requests-mock | 1.9.3 | >=1.12.1 |
| lxml | 4.9.1 | >=6.1.0 |
| aiohttp | 3.13.4 | >=3.13.5 |
| schedule | 1.1.0 | >=1.2.2 |
| PyJWT | 2.12.0 | >=2.12.1 |
| bs4 | 0.0.1 | >=0.0.2 |
| evdev | 1.5.0 | >=1.9.3 |
| cryptography | 46.0.6 | >=47.0.0 |
| msal | 1.33.0 | >=1.36.0 |
| python-dateutil | 2.8.2 | >=2.9.0 |
| pysmb | 1.2.9.1 | >=1.2.13 |
| pytz | 2023.3.post1 | >=2026.1 |
| grpcio | 1.60.1 | >=1.80.0 |
| protobuf | 5.29.6 | >=7.34.1 |
| pycarwings3 | 0.7.14 | >=0.7.14 |
| asyncio | 3.4.3 | >=4.0.0 |
| passlib | 1.7.4 | >=1.7.4 |
| pkce | 1.0.3 | >=1.0.3 |
| umodbus | 1.0.4 | >=1.0.4 |

---

## Git-Commits auf dem Branch

```
eb36a8034 Upgrade ocpp 1.0 to 2.1.0 and websockets 12.0 to 16.0
829472bd0 Upgrade paho-mqtt 1.6.1 to 2.1.0
46145edb2 Upgrade pymodbus 2.5.2 to 3.x
```

## Server-Test

```
● openwb2.service - "Regelung openWB 2.0"
     Active: active (running)
     Process: ExecStartPre=atreboot.sh (code=exited, status=0/SUCCESS)
     Main PID: python3 /var/www/html/openWB/packages/main.py
```

Web UI: HTTP 200 OK

## Bekannte Blocker fuer openWB/core

- **pymodbus 3.13.0 erfordert Python >=3.10** — openWB setzt aktuell Python 3.9 ein
- **paho-mqtt 2.1.0** nutzt `CallbackAPIVersion.VERSION1` (deprecated aber funktional)
- **websockets 16** hat weitere API-Aenderungen, aber ocpp.py ist die einzige betroffene Datei
