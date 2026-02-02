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


class AlertDDoS(BaseModel):
    id: str
    name: str
    prefix: str
    proto: str
    current_bps: float
    current_pps: float
    current_fps: float
    recommend_bps: float
    recommend_pps: float
    recommend_fps: float
    bps_alert: bool
    pps_alert: bool
    fps_alert: bool
