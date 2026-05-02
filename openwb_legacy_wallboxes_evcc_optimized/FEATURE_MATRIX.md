# Feature-Matrix

| Feature | go-e | KEBA UDP | SimpleEVSE WiFi |
|---|---:|---:|---:|
| Strom setzen | ja | ja | ja |
| Start/Stop | `frc`/`alw` | `ena` | `setStatus` |
| PV-Regelung | über openWB | über openWB | über openWB |
| Leistung | `nrg` | report 3 | falls Firmware liefert/berechnet |
| Ströme | `nrg` | report 3 | falls Firmware liefert/berechnet |
| Spannung | `nrg` | report 3 | falls Firmware liefert |
| Energie | `eto` | report 3 | `meterReading` falls vorhanden |
| RFID | best effort `trx/cards` | report 100 / optional start tag | best effort |
| Phasenerkennung | ja | ja | best effort |
| Phasenumschaltung | API v2 `psm` | nein/extern | nein/extern |
| CP-Unterbrechung | Stop-Fallback | Stop-Fallback | Stop-Fallback |
