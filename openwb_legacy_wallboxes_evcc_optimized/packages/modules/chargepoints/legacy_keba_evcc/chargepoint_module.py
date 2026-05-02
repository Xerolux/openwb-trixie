import json
import socket
from typing import Any, Dict, Optional

from helpermodules.utils.error_handling import CP_ERROR, ErrorTimerContext
from modules.chargepoints.legacy_keba_evcc.config import LegacyKebaEvcc
from modules.common.abstract_chargepoint import AbstractChargepoint
from modules.common.abstract_device import DeviceDescriptor
from modules.common.component_context import SingleComponentUpdateContext
from modules.common.component_state import ChargepointState
from modules.common.fault_state import ComponentInfo, FaultState
from modules.common.store import get_chargepoint_value_store

class _KebaUdp:
    PORT = 7090
    def __init__(self, ip: str, timeout: float):
        self.ip, self.timeout = ip, timeout

    def roundtrip(self, cmd: str) -> str:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(float(self.timeout))
        try:
            sock.sendto(cmd.encode(), (self.ip, self.PORT))
            data, _ = sock.recvfrom(4096)
            return data.decode(errors="replace")
        finally:
            sock.close()

    def send(self, cmd: str) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.sendto(cmd.encode(), (self.ip, self.PORT))
        finally:
            sock.close()

    def report(self, nr: int) -> Dict[str, Any]:
        raw = self.roundtrip(f"report {nr}")
        return json.loads(raw)

class ChargepointModule(AbstractChargepoint):
    def __init__(self, config: LegacyKebaEvcc) -> None:
        self.config = config
        self.store = get_chargepoint_value_store(config.id)
        self.fault_state = FaultState(ComponentInfo(config.id, "Ladepunkt", "chargepoint"))
        self.client_error_context = ErrorTimerContext(
            f"openWB/set/chargepoint/{config.id}/get/error_timestamp", CP_ERROR, hide_exception=True)

    def _client(self) -> _KebaUdp:
        ip = self.config.configuration.ip_address
        if not ip:
            raise ValueError("KEBA IP-Adresse fehlt")
        return _KebaUdp(ip, self.config.configuration.timeout)

    def set_current(self, current: float) -> None:
        if self.client_error_context.error_counter_exceeded():
            current = 0
        with SingleComponentUpdateContext(self.fault_state, update_always=False):
            with self.client_error_context:
                c = self._client()
                if current < self.config.configuration.min_current:
                    c.send("ena 0")
                    return
                if self.config.configuration.rfid_tag:
                    c.send(f"start {self.config.configuration.rfid_tag}")
                amps = max(self.config.configuration.min_current, min(self.config.configuration.max_current, int(round(current))))
                c.send("ena 1")
                c.send(f"curr {amps * 1000}")
                if self.config.configuration.enable_display:
                    c.send(f"display 1 10 10 0 S{amps}")

    def get_values(self) -> None:
        with SingleComponentUpdateContext(self.fault_state):
            with self.client_error_context:
                c = self._client()
                r2 = c.report(2)
                try:
                    r3 = c.report(3)
                except Exception:
                    r3 = {}
                try:
                    r100 = c.report(100)
                except Exception:
                    r100 = {}

                state_code = int(r2.get("State", 0) or 0)
                plug = int(r2.get("Plug", 0) or 0)
                currents = [
                    float(r3.get("I1", 0) or 0) / 1000,
                    float(r3.get("I2", 0) or 0) / 1000,
                    float(r3.get("I3", 0) or 0) / 1000,
                ]
                voltages = [
                    float(r3.get("U1", 0) or 0),
                    float(r3.get("U2", 0) or 0),
                    float(r3.get("U3", 0) or 0),
                ] if r3 else None
                power = float(r3.get("P", 0) or 0) / 1000
                imported = float(r3.get("E total", r3.get("E pres", 0)) or 0) / 10
                rfid = r100.get("RFID tag") or None

                if int(r2.get("Error1", 0) or 0) or int(r2.get("Error2", 0) or 0):
                    self.fault_state.error(f"KEBA Fehler Error1={r2.get('Error1')} Error2={r2.get('Error2')}")

                state = ChargepointState(
                    power=power,
                    currents=currents,
                    voltages=voltages,
                    imported=imported,
                    exported=0,
                    plug_state=plug >= 5,
                    charge_state=state_code == 3,
                    phases_in_use=sum(1 for i in currents if i > 0.3) or None,
                    rfid=rfid,
                    serial_number=r2.get("Serial") or r3.get("Serial"),
                    max_evse_current=int(r2.get("Max curr", 0) or 0) / 1000 if r2.get("Max curr") else self.config.configuration.max_current,
                    evse_current=int(r2.get("Curr user", 0) or 0) / 1000 if r2.get("Curr user") else None,
                )
                self.client_error_context.reset_error_counter()
            if self.client_error_context.error_counter_exceeded():
                state = ChargepointState(
                    plug_state=None,
                    charge_state=False,
                    imported=None,
                    exported=None,
                    currents=[0.0, 0.0, 0.0],
                    phases_in_use=0,
                    power=0,
                )
            self.store.set(state)

    def switch_phases(self, phases_to_use: int) -> None:
        self.fault_state.warning("KEBA UDP bietet keine universelle openWB-seitige Phasenumschaltung; externe IO-Aktion noetig.")

    def interrupt_cp(self, duration: int) -> None:
        with SingleComponentUpdateContext(self.fault_state, update_always=False):
            with self.client_error_context:
                self._client().send("ena 0")

    def clear_rfid(self) -> None:
        pass

    def add_conversion_loss_to_current(self, current: float) -> float:
        return current

    def subtract_conversion_loss_from_current(self, current: float) -> float:
        return current

chargepoint_descriptor = DeviceDescriptor(configuration_factory=LegacyKebaEvcc)
