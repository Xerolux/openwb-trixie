from typing import Optional
from modules.common.abstract_chargepoint import SetupChargepoint

class LegacySimpleEVSEEvccConfiguration:
    def __init__(self,
                 ip_address: Optional[str] = None,
                 timeout: int = 4,
                 min_current: int = 6,
                 max_current: int = 16,
                 phases_configured: int = 3,
                 use_set_status: bool = True):
        self.ip_address = ip_address
        self.timeout = timeout
        self.min_current = min_current
        self.max_current = max_current
        self.phases_configured = phases_configured
        self.use_set_status = use_set_status

class LegacySimpleEVSEEvcc(SetupChargepoint[LegacySimpleEVSEEvccConfiguration]):
    def __init__(self, name="SimpleEVSE WiFi Legacy evcc-geprüft", type="legacy_simpleevse_evcc", id=0, configuration=None):
        super().__init__(name, type, id, configuration or LegacySimpleEVSEEvccConfiguration())
