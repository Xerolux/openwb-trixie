from typing import Optional
from modules.common.abstract_chargepoint import SetupChargepoint

class LegacyGoEEvccConfiguration:
    def __init__(self,
                 ip_address: Optional[str] = None,
                 api_version: str = "auto",
                 timeout: int = 3,
                 min_current: int = 6,
                 max_current: int = 32,
                 enable_with_force_state: bool = True,
                 use_amx_for_legacy: bool = True,
                 allow_phase_switch: bool = True):
        self.ip_address = ip_address
        self.api_version = api_version
        self.timeout = timeout
        self.min_current = min_current
        self.max_current = max_current
        self.enable_with_force_state = enable_with_force_state
        self.use_amx_for_legacy = use_amx_for_legacy
        self.allow_phase_switch = allow_phase_switch

class LegacyGoEEvcc(SetupChargepoint[LegacyGoEEvccConfiguration]):
    def __init__(self, name="go-eCharger Legacy evcc-optimiert", type="legacy_goe_evcc", id=0, configuration=None):
        super().__init__(name, type, id, configuration or LegacyGoEEvccConfiguration())
