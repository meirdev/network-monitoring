from fastapi import APIRouter

from nm.models.alert import AlertThreshold
from nm.response import Response, encoder
from nm.services.alert import AlertServiceDep

router = APIRouter()


@router.get("/", response_model=Response[list[AlertThreshold]])
def get_alerts(alert_service: AlertServiceDep):
    alerts = alert_service.get_alerts()

    return encoder(alerts)
