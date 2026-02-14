from datetime import datetime, timezone
from typing import Annotated, Any, cast

from fastapi import Depends

from nm.models.alert import AlertDDoS, AlertThreshold
from nm.services._base import BaseService


class AlertService(BaseService):
    def get_threshold_alerts(
        self, date: datetime | None = None, max_duration: int = 60
    ) -> list[AlertThreshold]:
        if date is None:
            date = datetime.now(tz=timezone.utc)

        query = """
        WITH alerts AS (
            SELECT id, 'threshold' AS type, prefix, peak_bps, peak_pps, bandwidth_alert, packet_alert
            FROM flows.static_threshold_alerts_vw(date=%(date)s, max_duration=%(max_duration)s)
            UNION ALL
            SELECT id, 'zscore' AS type, prefix, peak_bps, peak_pps, bandwidth_alert, packet_alert
            FROM flows.dynamic_threshold_alerts_vw(date=%(date)s)
        )
        SELECT id, type, name, prefix, peak_bps, peak_pps, toBool(bandwidth_alert) AS bandwidth_alert, toBool(packet_alert) AS packet_alert
        FROM alerts LEFT JOIN flows.rules USING id
        """
        result = cast(
            list[tuple[Any, ...]],
            self.state.client_admin.execute(
                query,
                params={"max_duration": max_duration, "date": date},
            ),
        )

        return [
            AlertThreshold(
                id=row[0],
                type=row[1],
                name=row[2],
                prefix=row[3],
                peak_bps=row[4],
                peak_pps=row[5],
                bandwidth_alert=row[6],
                packet_alert=row[7],
            )
            for row in result
        ]

    def get_ddos_alerts(self, date: datetime | None = None) -> list[AlertDDoS]:
        if date is None:
            date = datetime.now(tz=timezone.utc)

        query = """
        SELECT
            id,
            name,
            prefix,
            proto,
            current_bps,
            current_pps,
            current_fps,
            recommend_bps,
            recommend_pps,
            recommend_fps,
            bps_alert,
            pps_alert,
            fps_alert
        FROM flows.advanced_ddos_alerts_vw(date=%(date)s, sensitivity='high')
        LEFT JOIN flows.rules USING id
        """
        result = cast(
            list[tuple[Any, ...]],
            self.state.client_admin.execute(query, params={"date": date}),
        )

        return [
            AlertDDoS(
                id=row[0],
                name=row[1],
                prefix=row[2],
                proto=row[3],
                current_bps=row[4],
                current_pps=row[5],
                current_fps=row[6],
                recommend_bps=row[7],
                recommend_pps=row[8],
                recommend_fps=row[9],
                bps_alert=row[10],
                pps_alert=row[11],
                fps_alert=row[12],
            )
            for row in result
        ]


AlertServiceDep = Annotated[AlertService, Depends(AlertService)]
