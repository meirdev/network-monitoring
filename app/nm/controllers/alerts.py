from fastapi import APIRouter

from nm.models.alert import AlertDDoS, AlertThreshold
from nm.response import Response, encoder
from nm.services.alert import AlertServiceDep

router = APIRouter()


@router.get("/thresholds", response_model=Response[list[AlertThreshold]])
def get_threshold_alerts(alert_service: AlertServiceDep):
    alerts = alert_service.get_threshold_alerts()

    return encoder(alerts)


@router.get("/ddos", response_model=Response[list[AlertDDoS]])
def get_ddos_alerts(alert_service: AlertServiceDep):
    alerts = alert_service.get_ddos_alerts()

    return encoder(alerts)
