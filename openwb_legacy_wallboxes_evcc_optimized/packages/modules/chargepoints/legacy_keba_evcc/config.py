from typing import Optional
from modules.common.abstract_chargepoint import SetupChargepoint

class LegacyKebaEvccConfiguration:
    def __init__(self,
                 ip_address: Optional[str] = None,
                 timeout: float = 1.5,
                 min_current: int = 6,
                 max_current: int = 32,
                 rfid_tag: Optional[str] = None,
                 enable_display: bool = True):
        self.ip_address = ip_address
        self.timeout = timeout
        self.min_current = min_current
        self.max_current = max_current
        self.rfid_tag = rfid_tag
        self.enable_display = enable_display

class LegacyKebaEvcc(SetupChargepoint[LegacyKebaEvccConfiguration]):
    def __init__(self, name="KEBA UDP Legacy evcc-optimiert", type="legacy_keba_evcc", id=0, configuration=None):
        super().__init__(name, type, id, configuration or LegacyKebaEvccConfiguration())
