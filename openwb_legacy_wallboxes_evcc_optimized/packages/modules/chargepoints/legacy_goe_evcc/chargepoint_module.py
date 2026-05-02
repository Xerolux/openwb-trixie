import json
import logging
from typing import Any, Dict, List, Optional, Tuple

from helpermodules.utils.error_handling import CP_ERROR, ErrorTimerContext
from modules.chargepoints.legacy_goe_evcc.config import LegacyGoEEvcc
from modules.common import req
from modules.common.abstract_chargepoint import AbstractChargepoint
from modules.common.abstract_device import DeviceDescriptor
from modules.common.component_context import SingleComponentUpdateContext
from modules.common.component_state import ChargepointState
from modules.common.fault_state import ComponentInfo, FaultState
from modules.common.store import get_chargepoint_value_store

log = logging.getLogger(__name__)

class _GoE:
    FILTER = "alw,car,eto,nrg,wh,trx,cards,amp,amx,frc,err,pnp,psm,sse,fwv"

    def __init__(self, ip: str, timeout: int, api_version: str):
        self.ip, self.timeout, self.api_version = ip, timeout, api_version
        self.session = req.get_http_session()

    def _url(self, path: str) -> str:
        return "http://%s%s" % (self.ip, path)

    def _json(self, path: str) -> Dict[str, Any]:
        r = self.session.get(self._url(path), timeout=self.timeout)
        r.raise_for_status()
        return r.json()

    def status(self) -> Tuple[Dict[str, Any], bool]:
        if self.api_version == "v1":
            return self._json("/status"), False
        if self.api_version == "v2":
            return self._json("/api/status?filter=" + self.FILTER), True
        try:
            return self._json("/api/status?filter=" + self.FILTER), True
        except Exception:
            return self._json("/status"), False

    def update(self, payload: str, v2: bool) -> None:
        if v2:
            path = "/api/set?" + payload
        else:
            path = "/mqtt?payload=" + payload
        r = self.session.get(self._url(path), timeout=(self.timeout, None))
        r.raise_for_status()

class ChargepointModule(AbstractChargepoint):
    def __init__(self, config: LegacyGoEEvcc) -> None:
        self.config = config
        self.store = get_chargepoint_value_store(config.id)
        self.fault_state = FaultState(ComponentInfo(config.id, "Ladepunkt", "chargepoint"))
        self.client_error_context = ErrorTimerContext(
            f"openWB/set/chargepoint/{config.id}/get/error_timestamp", CP_ERROR, hide_exception=True)

    def _client(self) -> _GoE:
        ip = self.config.configuration.ip_address
        if not ip:
            raise ValueError("go-e IP-Adresse fehlt")
        return _GoE(ip, int(self.config.configuration.timeout), self.config.configuration.api_version)

    def set_current(self, current: float) -> None:
        if self.client_error_context.error_counter_exceeded():
            current = 0
        with SingleComponentUpdateContext(self.fault_state, update_always=False):
            with self.client_error_context:
                c = self._client()
                data, v2 = c.status()
                min_a = int(self.config.configuration.min_current or 6)
                max_a = min(int(self.config.configuration.max_current or 32), int(data.get("ama") or data.get("cbl") or 32))
                if current < min_a:
                    c.update("frc=1" if v2 else "alw=0", v2)
                    return

                amps = max(min_a, min(max_a, int(round(current))))
                if self.config.configuration.enable_with_force_state:
                    c.update("frc=2" if v2 else "alw=1", v2)
                if v2:
                    c.update(f"amp={amps}", True)
                else:
                    key = "amx" if self.config.configuration.use_amx_for_legacy else "amp"
                    c.update(f"{key}={amps}", False)

    def get_values(self) -> None:
        with SingleComponentUpdateContext(self.fault_state):
            with self.client_error_context:
                data, v2 = self._client().status()
                nrg = data.get("nrg") or []
                currents = self._currents(nrg)
                voltages = self._voltages(nrg)
                powers = self._powers(nrg)
                car = int(data.get("car") or 0)
                imported = data.get("eto")
                if imported is not None:
                    imported = float(imported)
                rfid = self._rfid(data)
                state = ChargepointState(
                    power=self._power(nrg, powers),
                    powers=powers,
                    currents=currents,
                    voltages=voltages,
                    imported=imported,
                    exported=0,
                    plug_state=car in (2, 3, 4),
                    charge_state=car == 2,
                    phases_in_use=self._phases(data, currents),
                    rfid=rfid,
                    serial_number=str(data.get("sse")) if data.get("sse") is not None else None,
                    max_evse_current=data.get("amx") or data.get("ama") or data.get("cbl"),
                    evse_current=data.get("amp") or data.get("amx"),
                    version=str(data.get("fwv")) if data.get("fwv") is not None else None,
                )
                if data.get("err") not in (None, 0, "0"):
                    self.fault_state.error(f"go-e Fehlercode {data.get('err')}")
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
    def _currents(nrg: List[Any]) -> List[float]:
        if len(nrg) >= 7:
            return [float(nrg[4] or 0), float(nrg[5] or 0), float(nrg[6] or 0)]
        return [0.0, 0.0, 0.0]

    @staticmethod
    def _voltages(nrg: List[Any]) -> Optional[List[float]]:
        if len(nrg) >= 3:
            return [float(nrg[0] or 0), float(nrg[1] or 0), float(nrg[2] or 0)]
        return None

    @staticmethod
    def _powers(nrg: List[Any]) -> Optional[List[float]]:
        if len(nrg) >= 11:
            return [float(nrg[8] or 0), float(nrg[9] or 0), float(nrg[10] or 0)]
        return None

    @staticmethod
    def _power(nrg: List[Any], powers: Optional[List[float]]) -> float:
        if len(nrg) >= 12:
            return float(nrg[11] or 0)
        return float(sum(powers or []))

    @staticmethod
    def _phases(data: Dict[str, Any], currents: List[float]) -> Optional[int]:
        active = sum(1 for i in currents if i > 0.3)
        if active:
            return active
        pnp = data.get("pnp")
        return int(pnp) if isinstance(pnp, int) and pnp in (1, 3) else None

    @staticmethod
    def _rfid(data: Dict[str, Any]) -> Optional[str]:
        for key in ("trx", "lri", "tsi"):
            value = data.get(key)
            if value:
                return str(value)
        cards = data.get("cards")
        if isinstance(cards, list) and cards:
            return str(cards[0])
        return None

    def switch_phases(self, phases_to_use: int) -> None:
        if not self.config.configuration.allow_phase_switch:
            return
        if phases_to_use not in (1, 3):
            raise ValueError("go-e unterstuetzt nur 1p/3p")
        with SingleComponentUpdateContext(self.fault_state, update_always=False):
            with self.client_error_context:
                c = self._client()
                data, v2 = c.status()
                if not v2:
                    self.fault_state.warning("go-e Phasenumschaltung braucht API v2")
                    return
                c.update(f"psm={1 if phases_to_use == 1 else 2}", True)

    def interrupt_cp(self, duration: int) -> None:
        with SingleComponentUpdateContext(self.fault_state, update_always=False):
            with self.client_error_context:
                c = self._client()
                data, v2 = c.status()
                c.update("frc=1" if v2 else "alw=0", v2)

    def clear_rfid(self) -> None:
        pass

    def add_conversion_loss_to_current(self, current: float) -> float:
        return current

    def subtract_conversion_loss_from_current(self, current: float) -> float:
        return current

chargepoint_descriptor = DeviceDescriptor(configuration_factory=LegacyGoEEvcc)
