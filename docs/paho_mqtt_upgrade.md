# paho-mqtt 1.6.1 → 2.1.0 Upgrade: Dokumentation

**Datum:** 2026-05-03
**Status:** **ERFOLGREICH — openWB laeuft mit paho-mqtt 2.1.0**
**Requires-Python:** >=3.7 (kompatibel mit Python 3.9+)

---

## Ergebnis

```
● openwb2.service - "Regelung openWB 2.0"
     Active: active (running)
     Process: ExecStartPre=atreboot.sh (code=exited, status=0/SUCCESS)
```

---

## Breaking Change in paho-mqtt 2.0

`mqtt.Client()` erfordert jetzt `CallbackAPIVersion` als erstes Argument:

```python
# ALT (1.6.1):
client = mqtt.Client("my-client-id")
client = mqtt.Client()

# NEU (2.1.0):
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id="my-client-id")
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
```

`mqtt.Client("string")` wirft in 2.x einen `ValueError`.

Hinweis: `CallbackAPIVersion.VERSION1` ist deprecated (DeprecationWarning), 
funktioniert aber. VERSION2 aendert die Callback-Signaturen 
(on_connect, on_message etc.), was weitaus mehr Aenderungen erfordern wuerde.

---

## Geaenderte Dateien (8 Dateien)

| Datei | Aenderung |
|-------|-----------|
| `requirements.txt` | `paho_mqtt==1.6.1` → `paho-mqtt>=2.1.0` |
| `packages/helpermodules/broker.py` | 2x Client() Konstruktor |
| `packages/modules/smarthome/mqtt/off.py` | Client() mit String-ID |
| `packages/modules/smarthome/mqtt/on.py` | Client() mit String-ID |
| `packages/modules/smarthome/mqtt/watt.py` | Client() mit String-Concat |
| `packages/smarthome/smartcommon.py` | 3x Client() (String-Concat + String-ID) |
| `runs/remoteSupport/remoteSupport.py` | Client() mit f-String |
| `simpleAPI/simpleAPI_mqtt.py` | Client() ohne Args |

---

## Migrations-Regeln

```
mqtt.Client("id")                    → mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id="id")
mqtt.Client("str" + expr)            → mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id="str" + expr)
mqtt.Client(f"...")                  → mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=f"...")
mqtt.Client(self.name)               → mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=self.name)
mqtt.Client()                        → mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
```

Unveraendert:
- `import paho.mqtt.client as mqtt` — gleicher Import
- `paho.mqtt.publish` — unverandert
- `client.connect()`, `client.publish()`, `client.subscribe()` — unverandert
- `on_connect()`, `on_message()` Callbacks — unverandert mit VERSION1

---

## Automatisches Migrationsskript

```python
#!/usr/bin/env python3
import re, os

def upgrade_file(filepath):
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    original = content

    # mqtt.Client("string_id")
    content = re.sub(
        r'mqtt\.Client\("([^"]+)"\)',
        r'mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id="\1")',
        content
    )
    # mqtt.Client("string" + expr)
    content = re.sub(
        r'mqtt\.Client\(("(?:[^"]*)"[^)]*)\)',
        r'mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=\1)',
        content
    )
    # mqtt.Client(variable)
    content = re.sub(
        r'mqtt\.Client\((?!mqtt\.CallbackAPIVersion)([a-zA-Z_][a-zA-Z0-9_.]*)\)',
        r'mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=\1)',
        content
    )
    # mqtt.Client(f"...")
    content = re.sub(
        r'mqtt\.Client\((f"[^"]*")\)',
        r'mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=\1)',
        content
    )
    # mqtt.Client()
    content = content.replace(
        'mqtt.Client()',
        'mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)'
    )

    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    return False

# Usage:
for root, dirs, files in os.walk('/var/www/html/openWB'):
    dirs[:] = [d for d in dirs if d != '__pycache__']
    for fn in files:
        if fn.endswith('.py'):
            fp = os.path.join(root, fn)
            if upgrade_file(fp):
                print(f'Fixed: {fp}')
```
