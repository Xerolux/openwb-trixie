from typing import Any, Dict, Optional, List

from helpermodules.utils.error_handling import CP_ERROR, ErrorTimerContext
from modules.chargepoints.legacy_simpleevse_evcc.config import LegacySimpleEVSEEvcc
from modules.common import req
from modules.common.abstract_chargepoint import AbstractChargepoint
from modules.common.abstract_device import DeviceDescriptor
from modules.common.component_context import SingleComponentUpdateContext
from modules.common.component_state import ChargepointState
from modules.common.fault_state import ComponentInfo, FaultState
from modules.common.store import get_chargepoint_value_store

class _SimpleEVSEWifi:
    def __init__(self, ip: str, timeout: int):
        self.ip, self.timeout = ip, timeout
        self.session = req.get_http_session()

    def _url(self, path: str) -> str:
        return f"http://{self.ip}{path}"

    def get_parameters(self) -> Dict[str, Any]:
        r = self.session.get(self._url("/getParameters"), timeout=self.timeout)
        r.raise_for_status()
        data = r.json()
        if isinstance(data, dict) and data.get("list"):
            return data["list"][0]
        return data

    def set_status(self, active: bool) -> None:
        self.session.get(self._url(f"/setStatus?active={'true' if active else 'false'}"), timeout=(self.timeout, None)).raise_for_status()

    def set_current(self, current: int) -> None:
        self.session.get(self._url(f"/setCurrent?current={current}"), timeout=(self.timeout, None)).raise_for_status()

class ChargepointModule(AbstractChargepoint):
    def __init__(self, config: LegacySimpleEVSEEvcc) -> None:
        self.config = config
        self.store = get_chargepoint_value_store(config.id)
        self.fault_state = FaultState(ComponentInfo(config.id, "Ladepunkt", "chargepoint"))
        self.client_error_context = ErrorTimerContext(
            f"openWB/set/chargepoint/{config.id}/get/error_timestamp", CP_ERROR, hide_exception=True)

    def _client(self) -> _SimpleEVSEWifi:
        ip = self.config.configuration.ip_address
        if not ip:
            raise ValueError("SimpleEVSE IP-Adresse fehlt")
        return _SimpleEVSEWifi(ip, self.config.configuration.timeout)

    def set_current(self, current: float) -> None:
        if self.client_error_context.error_counter_exceeded():
            current = 0
        with SingleComponentUpdateContext(self.fault_state, update_always=False):
            with self.client_error_context:
                c = self._client()
                if current < self.config.configuration.min_current:
                    if self.config.configuration.use_set_status:
                        c.set_status(False)
                    else:
                        c.set_current(0)
                    return
                amps = max(self.config.configuration.min_current, min(self.config.configuration.max_current, int(round(current))))
                if self.config.configuration.use_set_status:
                    c.set_status(True)
                c.set_current(amps)

    def get_values(self) -> None:
        with SingleComponentUpdateContext(self.fault_state):
            with self.client_error_context:
                p = self._client().get_parameters()
                active = self._bool(p.get("evseState"))
                vehicle = self._int(p.get("vehicleState"))
                plug_state = vehicle in (2, 3) if vehicle is not None else None
                charge_state = vehicle == 3 and active is not False

                currents = self._currents(p, charge_state)
                voltages = self._voltages(p)
                power = self._power(p, currents, voltages)
                imported = self._imported(p)
                rfid = p.get("RFIDUID") or p.get("rfid") or p.get("tag") or None

                state = ChargepointState(
                    power=power,
                    currents=currents,
                    voltages=voltages,
                    imported=imported,
                    exported=0,
                    plug_state=plug_state,
                    charge_state=charge_state,
                    phases_in_use=sum(1 for i in currents if i > 0.3) or (self.config.configuration.phases_configured if charge_state else None),
                    rfid=rfid,
                    serial_number=str(p.get("mac") or p.get("serial") or "") or None,
                    max_evse_current=p.get("maxCurrent") or self.config.configuration.max_current,
                    evse_current=p.get("actualCurrent") or p.get("current"),
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

    @staticmethod
    def _bool(v: Any) -> Optional[bool]:
        if isinstance(v, bool):
            return v
        if isinstance(v, str):
            return v.lower() in ("true", "1", "yes", "on")
        if isinstance(v, (int, float)):
            return bool(v)
        return None

    @staticmethod
    def _int(v: Any) -> Optional[int]:
        try:
            return int(v)
        except Exception:
            return None

    def _currents(self, p: Dict[str, Any], charge_state: bool) -> List[float]:
        keys = ["currentP1", "currentP2", "currentP3"]
        if any(k in p for k in keys):
            return [float(p.get(k) or 0) for k in keys]
        if charge_state:
            a = float(p.get("actualCurrent") or p.get("current") or 0)
            return [a if i < int(self.config.configuration.phases_configured) else 0.0 for i in range(3)]
        return [0.0, 0.0, 0.0]

    @staticmethod
    def _voltages(p: Dict[str, Any]) -> Optional[List[float]]:
        keys = ["voltageP1", "voltageP2", "voltageP3"]
        return [float(p.get(k) or 0) for k in keys] if any(k in p for k in keys) else None

    @staticmethod
    def _power(p: Dict[str, Any], currents: List[float], voltages: Optional[List[float]]) -> float:
        if p.get("actualPower") is not None:
            val = float(p.get("actualPower") or 0)
            return val * 1000 if abs(val) < 1000 else val
        if voltages:
            return sum(v * i for v, i in zip(voltages, currents))
        return 230 * sum(currents)

    @staticmethod
    def _imported(p: Dict[str, Any]) -> Optional[float]:
        val = p.get("meterReading") or p.get("imported") or p.get("energy")
        if val is None:
            return None
        f = float(val)
        return f * 1000 if f < 100000 else f

    def switch_phases(self, phases_to_use: int) -> None:
        self.fault_state.warning("SimpleEVSE WiFi hat keine universelle HTTP-Phasenumschaltung; externe IO-Aktion noetig.")

    def interrupt_cp(self, duration: int) -> None:
        with SingleComponentUpdateContext(self.fault_state, update_always=False):
            with self.client_error_context:
                self._client().set_status(False)

    def clear_rfid(self) -> None:
        pass

    def add_conversion_loss_to_current(self, current: float) -> float:
        return current

    def subtract_conversion_loss_from_current(self, current: float) -> float:
        return current

chargepoint_descriptor = DeviceDescriptor(configuration_factory=LegacySimpleEVSEEvcc)
