from datetime import datetime

from pydantic import BaseModel


class AlertThreshold(BaseModel):
    id: str
    type: str
    name: str
    prefix: str
    peak_bps: float
    peak_pps: float
    bandwidth_alert: bool
    packet_alert: bool
    timestamp: datetime
