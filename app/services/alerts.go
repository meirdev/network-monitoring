package services

import (
	"context"
	"fmt"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
)

const MaxDuration = 60

type ThresholdAlert struct {
	Id             string `ch:"id" json:"id"`
	Name           string `ch:"name" json:"name"`
	BandwidthAlert bool   `ch:"bandwidth_alert" json:"bandwidth_alert"`
	PacketAlert    bool   `ch:"packet_alert" json:"packet_alert"`
}

type AlertService struct {
	Connection driver.Conn
}

func NewAlertService(conn driver.Conn) *AlertService {
	return &AlertService{
		Connection: conn,
	}
}

func (s *AlertService) GetThresholdAlerts(ctx context.Context) (*[]ThresholdAlert, error) {
	query := `
	WITH alerts AS (
		SELECT id, bandwidth_alert, packet_alert FROM flows.static_threshold_alerts_vw(date=now(), max_duration={max_duration:UInt64})
		UNION ALL
		SELECT id, bandwidth_alert, packet_alert FROM flows.dynamic_threshold_alerts_vw(date=now())
	)
	SELECT id, name, toBool(bandwidth_alert) AS bandwidth_alert, toBool(packet_alert) AS packet_alert FROM alerts LEFT JOIN flows.rules USING id
	`

	chCtx := clickhouse.Context(ctx, clickhouse.WithParameters(clickhouse.Parameters{
		"max_duration": fmt.Sprintf("%d", MaxDuration),
	}))

	rows, err := s.Connection.Query(chCtx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []ThresholdAlert
	for rows.Next() {
		var result ThresholdAlert
		if err := rows.ScanStruct(&result); err != nil {
			return nil, err
		}
		results = append(results, result)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &results, nil
}
