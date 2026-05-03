# pymodbus 2.5.2 → 3.13.0 Upgrade: Erfolgreich angewendet

**Datum:** 2026-05-03
**Server:** 192.168.178.32 (Debian Trixie 13.4, Python 3.13.5)
**Von:** pymodbus **2.5.2**
**Nach:** pymodbus **3.13.0**
**Status:** **ERFOLGREICH — openWB laeuft mit pymodbus 3.13.0**

---

## Ergebnis

```
● openwb2.service - "Regelung openWB 2.0"
     Active: active (running)
     Process: ExecStartPre=atreboot.sh (code=exited, status=0/SUCCESS)
     Main PID: python3 /var/www/html/openWB/packages/main.py
```

- pymodbus 3.13.0 installiert und aktiv
- Alle Python-Dateien kompilieren fehlerfrei
- Service startet ohne Fehler
- Web-Interface erreichbar (HTTP 200)
- `atreboot.sh` pip-installiert pymodbus 3.13.0 (nicht mehr 2.5.2)

---

## 1. pymodbus 3.13.0 API-Referenz (VERIFIZIERT auf dem Server)

### Was sich geaendert hat

| 2.x (alt) | 3.13.0 (neu) | Typ |
|-----------|-----------|-----|
| `from pymodbus.client.sync import ModbusTcpClient` | `from pymodbus.client import ModbusTcpClient` | Import |
| `from pymodbus.client.sync import ModbusSerialClient` | `from pymodbus.client import ModbusSerialClient` | Import |
| `from pymodbus.transaction import ModbusSocketFramer` | `from pymodbus.framer import FramerType` | Import |
| `from pymodbus.transaction import ModbusRtuFramer` | `from pymodbus.framer import FramerType` | Import |
| `from pymodbus.constants import Endian` | **ENTFALLEN** — lokale Klasse | Entfernt |
| `from pymodbus.payload import BinaryPayloadBuilder` | **ENTFALLEN** — lokale Implementierung | Entfernt |
| `from pymodbus.payload import BinaryPayloadDecoder` | **ENTFALLEN** — lokale Implementierung | Entfernt |
| `unit=<id>` | `device_id=<id>` (keyword-only) | Geaendert |
| `ModbusSerialClient(method="rtu", port=X)` | `ModbusSerialClient(X, framer=FramerType.RTU)` | Konstruktor |
| `ModbusTcpClient(host, port, framer)` | `ModbusTcpClient(host, port=port, framer=framer)` | keyword-only |
| `read_holding_registers(addr, count, unit=x)` | `read_holding_registers(addr, count=count, device_id=x)` | keyword-only |
| `response.getRegister(i)` | `response.registers[i]` | Geaendert |

### Was GLEICH geblieben ist

- `from pymodbus.exceptions import ConnectionException, ModbusIOException` — unverandert
- `response.isError()` — unverandert
- `response.registers` — unverandert
- `client.connect()` / `client.close()` / `client.is_socket_open()` — unverandert
- `client.__enter__()` / `client.__exit__()` — unverandert
- `ModbusUdpClient` — unverandert

### Konstruktoren (Signaturen)

```python
ModbusTcpClient(host: str, *,
    framer: FramerType = FramerType.SOCKET,
    port: int = 502,
    timeout: float = 3,
    retries: int = 3, ...)

ModbusSerialClient(port: str, *,
    framer: FramerType = FramerType.RTU,
    baudrate: int = 19200,
    bytesize: int = 8,
    parity: str = 'N',
    stopbits: int = 1,
    timeout: float = 3, ...)

# WICHTIG: port ist POSITIONAL_ONLY bei SerialClient!
# framer, baudrate etc. sind KEYWORD_ONLY
```

### Methoden-Signaturen

```python
read_holding_registers(address, *, count=1, device_id=1)
read_input_registers(address, *, count=1, device_id=1)
read_coils(address, *, count=1, device_id=1)
write_registers(address, values, *, device_id=1)    # values ist positional
write_register(address, value, *, device_id=1)      # value ist positional
write_coil(address, value, *, device_id=1)           # value ist positional
```

---

## 2. Durchgefuehrte Migrationsschritte

### Schritt 1: requirements.txt

```bash
# Vorher: pymodbus==2.5.2
# Nachher:
sed -i 's/pymodbus==2.5.2/pymodbus>=3.13.0/' /var/www/html/openWB/requirements.txt
```

**Warum wichtig:** `atreboot.sh` fuehrt bei jedem Service-Start `pip install -r requirements.txt` aus. Oh diese Aenderung wuerde pymodbus bei jedem Start auf 2.5.2 zurueckgesetzt werden.

### Schritt 2: pymodbus installieren

```bash
/opt/openwb-venv/bin/pip install 'pymodbus>=3.13.0'
```

### Schritt 3: pymodbus_compat.py (NEUE DATEI)

Erstellt unter `/var/www/html/openWB/packages/modules/common/pymodbus_compat.py`.

Diese Datei bietet lokale Implementierungen fuer die entfernten Klassen:
- `Endian` (Big/Little Enum)
- `BinaryPayloadDecoder` (struct-basiert)
- `BinaryPayloadBuilder` (struct-basiert)

Siehe Anhang A fuer den vollstaendigen Code.

### Schritt 4: Globale sed-Ersetzungen

```bash
cd /var/www/html/openWB

# 4a: Import-Pfade
find . -name '*.py' -not -path '*__pycache__*' -print0 | xargs -0 sed -i \
    -e 's/from pymodbus\.client\.sync import/from pymodbus.client import/g' \
    -e 's/from pymodbus\.transaction import ModbusSocketFramer/from pymodbus.framer import FramerType/g' \
    -e 's/from pymodbus\.transaction import ModbusRtuFramer/from pymodbus.framer import FramerType/g' \
    -e 's/from pymodbus\.constants import Endian/from modules.common.pymodbus_compat import Endian/g' \
    -e 's/from pymodbus\.payload import Endian/from modules.common.pymodbus_compat import Endian/g' \
    -e 's/from pymodbus\.payload import BinaryPayloadBuilder, BinaryPayloadDecoder/from modules.common.pymodbus_compat import BinaryPayloadBuilder, BinaryPayloadDecoder/g' \
    -e 's/from pymodbus\.payload import BinaryPayloadDecoder/from modules.common.pymodbus_compat import BinaryPayloadDecoder/g' \
    -e 's/from pymodbus\.payload import BinaryPayloadBuilder/from modules.common.pymodbus_compat import BinaryPayloadBuilder/g' \
    -e 's/from pymodbus\.payload import BinaryPayloadBuilder, Endian/from modules.common.pymodbus_compat import BinaryPayloadBuilder, Endian/g'

# 4b: unit= -> device_id=
find . -name '*.py' -not -path '*__pycache__*' -print0 | xargs -0 sed -i \
    -e 's/\bunit=/device_id=/g'

# 4c: Framer-Klassen -> FramerType Enum
find . -name '*.py' -not -path '*__pycache__*' -print0 | xargs -0 sed -i \
    -e 's/\bModbusSocketFramer\b/FramerType.SOCKET/g' \
    -e 's/\bModbusRtuFramer\b/FramerType.RTU/g'
```

### Schritt 5: Manuelle Fixes

**modbus.py** (Kern-Wrapper):
- `read_register_method(address, number_of_addresses, **kwargs)` → `...count=number_of_addresses, **kwargs)`
- `read_register_method(start_address, count, **kwargs)` → `...count=count, **kwargs)`
- `self._delegate.read_coils(address, count, **kwargs)` → `...count=count, **kwargs)`
- `ModbusTcpClient(host, port, framer, **kwargs)` → `ModbusTcpClient(host, port=port, framer=framer, **kwargs)`
- `ModbusUdpClient(host, port, **kwargs)` → `ModbusUdpClient(host, port=port, **kwargs)`
- `ModbusSerialClient(method="rtu", port=port, ...)` → `ModbusSerialClient(port, framer=FramerType.RTU, ...)`
- `framer: type[ModbusSocketFramer] = ModbusSocketFramer` → `framer=FramerType.SOCKET`

**Smarthome-Dateien** (direkte Client-Nutzung):
- `ModbusTcpClient(SERVER_HOST, SERVER_PORT)` → `ModbusTcpClient(SERVER_HOST, port=SERVER_PORT)`
- `client.read_holding_registers(addr, count, device_id=x)` → `...count=count, device_id=x)`
- `rr.getRegister(i)` → `rr.registers[i]`

**runs/*.py**:
- `ModbusSerialClient(method="rtu", port=seradd, ...)` → `ModbusSerialClient(seradd, ...)`
- `client.read_holding_registers(readreg, reganzahl, ...)` → `...count=reganzahl, ...)`

**conftest.py** (Test-Mocks):
- `pymodbus.client.sync` → `pymodbus.client`
- `pymodbus.transaction` → `pymodbus.framer` (mit FramerType Mock)

### Schritt 6: Service starten

```bash
systemctl start openwb2
```

---

## 3. Geaenderte Dateien

### Neue Datei
- `packages/modules/common/pymodbus_compat.py` — Endian + BinaryPayload Shim

### Kern-Module
- `packages/modules/common/modbus.py` — Importe, Konstruktoren, keyword-only args
- `packages/modules/common/hardware_check.py` — Importe
- `packages/modules/conftest.py` — Test-Mocks

### Runs-Scripts
- `runs/readmodbus.py`
- `runs/evsewritembusdev.py`
- `runs/evse_write_modbus.py` (device_id= via sed)
- `runs/evse_read_modbus.py` (device_id= via sed)

### Smarthome-Module (direkte Client-Nutzung)
- `packages/modules/smarthome/we514/watt.py`
- `packages/modules/smarthome/nxdacxx/off.py`, `on.py`, `watt.py`
- `packages/modules/smarthome/acthor/watt.py`
- `packages/modules/smarthome/lambda_/off.py`, `on.py`, `watt.py`
- `packages/modules/smarthome/elwa/watt.py`
- `packages/modules/smarthome/viessmann/off.py`, `on.py`
- `packages/modules/smarthome/nibe/watt.py`
- `packages/modules/smarthome/idm/watt.py`
- `packages/modules/smarthome/vampair/off.py`, `on.py`, `watt.py`
- `packages/modules/smarthome/ratiotherm/watt.py`
- `packages/modules/smarthome/stiebel/off.py`, `on.py`
- `packages/modules/smarthome/askoheat/watt.py`

### Device-Module (160+ Dateien, nur unit= → device_id=)
Alle Dateien in `packages/modules/devices/*/` die `unit=` verwendeten.

### Tools
- `packages/tools/modbus_finder.py`
- `packages/tools/modbus_tester.py`
- `packages/modbus_control_tester.py`

### Konfiguration
- `requirements.txt` — `pymodbus==2.5.2` → `pymodbus>=3.13.0`

---

## 4. Rollback-Plan

Falls Probleme auftreten:

```bash
systemctl stop openwb2
rm -rf /var/www/html/openWB
mv /var/www/html/openWB.bak2 /var/www/html/openWB
rm -rf /opt/openwb-venv
mv /opt/openwb-venv.bak2 /opt/openwb-venv
systemctl start openwb2
```

Die Backups liegen unter:
- `/var/www/html/openWB.bak2` (vollstaendiges openWB-Verzeichnis)
- `/opt/openwb-venv.bak2` (vollstaendiges venv mit pymodbus 2.5.2)

---

## Anhang A: pymodbus_compat.py

```python
import struct


class Endian:
    Big = "big"
    Little = "little"


class BinaryPayloadDecoder:
    def __init__(self, payload, byteorder="big", wordorder="big"):
        self._payload = payload
        self._bo = byteorder
        self._wo = wordorder
        self._ptr = 0

    @classmethod
    def fromRegisters(cls, registers, byteorder="big", wordorder="big"):
        if wordorder == "little":
            registers = list(reversed(registers))
        raw = b""
        for r in registers:
            raw += struct.pack(">H", r)
        return cls(raw, byteorder, wordorder)

    def reset(self):
        self._ptr = 0

    def skip_bytes(self, n):
        self._ptr += n

    def _decode(self, fmt):
        sz = struct.calcsize(fmt)
        data = self._payload[self._ptr:self._ptr + sz]
        self._ptr += sz
        if ">" not in fmt and "<" not in fmt:
            fmt = ">" + fmt
        return struct.unpack(fmt, data)[0]

    def decode_8bit_uint(self):
        return self._decode("B")

    def decode_16bit_uint(self):
        return self._decode(">H")

    def decode_16bit_int(self):
        return self._decode(">h")

    def decode_32bit_uint(self):
        return self._decode(">I")

    def decode_32bit_int(self):
        return self._decode(">i")

    def decode_64bit_uint(self):
        return self._decode(">Q")

    def decode_64bit_int(self):
        return self._decode(">q")

    def decode_32bit_float(self):
        return self._decode(">f")

    def decode_64bit_float(self):
        return self._decode(">d")


class BinaryPayloadBuilder:
    def __init__(self, byteorder="big", wordorder="big"):
        self._bo = byteorder
        self._wo = wordorder
        self._regs = []

    def reset(self):
        self._regs = []

    def _add(self, value, fmt):
        if ">" not in fmt and "<" not in fmt:
            fmt = ">" + fmt
        data = struct.pack(fmt, value)
        regs = []
        for i in range(0, len(data), 2):
            chunk = data[i:i+2]
            if len(chunk) == 1:
                chunk = b"\x00" + chunk
            regs.append(struct.unpack(">H", chunk)[0])
        if self._wo == "little":
            regs.reverse()
        self._regs.extend(regs)

    def add_8bit_uint(self, v):
        self._add(v, "B")

    def add_16bit_uint(self, v):
        self._add(v, ">H")

    def add_16bit_int(self, v):
        self._add(v, ">h")

    def add_32bit_uint(self, v):
        self._add(v, ">I")

    def add_32bit_int(self, v):
        self._add(v, ">i")

    def add_64bit_uint(self, v):
        self._add(v, ">Q")

    def add_64bit_int(self, v):
        self._add(v, ">q")

    def add_32bit_float(self, v):
        self._add(v, ">f")

    def add_64bit_float(self, v):
        self._add(v, ">d")

    def to_registers(self):
        return list(self._regs)
```

---

## Anhang B: Migration als Einzeiler

```bash
# 1. Backup
cp -a /var/www/html/openWB /var/www/html/openWB.bak
cp -a /opt/openwb-venv /opt/openwb-venv.bak

# 2. requirements.txt + pip upgrade
sed -i 's/pymodbus==2.5.2/pymodbus>=3.13.0/' /var/www/html/openWB/requirements.txt
/opt/openwb-venv/bin/pip install 'pymodbus>=3.13.0'

# 3. Globale Ersetzungen
cd /var/www/html/openWB
find . -name '*.py' -not -path '*__pycache__*' -print0 | xargs -0 sed -i \
    -e 's/from pymodbus\.client\.sync import/from pymodbus.client import/g' \
    -e 's/from pymodbus\.transaction import ModbusSocketFramer/from pymodbus.framer import FramerType/g' \
    -e 's/from pymodbus\.transaction import ModbusRtuFramer/from pymodbus.framer import FramerType/g' \
    -e 's/from pymodbus\.constants import Endian/from modules.common.pymodbus_compat import Endian/g' \
    -e 's/from pymodbus\.payload import Endian/from modules.common.pymodbus_compat import Endian/g' \
    -e 's/from pymodbus\.payload import BinaryPayloadBuilder, BinaryPayloadDecoder/from modules.common.pymodbus_compat import BinaryPayloadBuilder, BinaryPayloadDecoder/g' \
    -e 's/from pymodbus\.payload import BinaryPayloadDecoder/from modules.common.pymodbus_compat import BinaryPayloadDecoder/g' \
    -e 's/from pymodbus\.payload import BinaryPayloadBuilder/from modules.common.pymodbus_compat import BinaryPayloadBuilder/g' \
    -e 's/from pymodbus\.payload import BinaryPayloadBuilder, Endian/from modules.common.pymodbus_compat import BinaryPayloadBuilder, Endian/g' \
    -e 's/\bunit=/device_id=/g' \
    -e 's/\bModbusSocketFramer\b/FramerType.SOCKET/g' \
    -e 's/\bModbusRtuFramer\b/FramerType.RTU/g'

# 4. pymodbus_compat.py kopieren (siehe Anhang A)
# 5. Manuelle Fixes in modbus.py, smarthome/*, runs/* (siehe Schritt 5 oben)
# 6. Service starten
systemctl restart openwb2
```

**Hinweis:** Die manuellen Fixes in Schritt 5 sind essentiell und koennen nicht per sed automatisiert werden, da sie kontextabhaengig sind.
