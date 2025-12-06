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

type DDoSAlert struct {
	Id           string  `ch:"id" json:"id"`
	Name         string  `ch:"name" json:"name"`
	Prefix       string  `ch:"prefix" json:"prefix"`
	Proto        string  `ch:"proto" json:"proto"`
	CurrentBPS   float64 `ch:"current_bps" json:"current_bps"`
	CurrentPPS   float64 `ch:"current_pps" json:"current_pps"`
	CurrentFPS   float64 `ch:"current_fps" json:"current_fps"`
	RecommendBPS float64 `ch:"recommend_bps" json:"recommend_bps"`
	RecommendPPS float64 `ch:"recommend_pps" json:"recommend_pps"`
	RecommendFPS float64 `ch:"recommend_fps" json:"recommend_fps"`
	BPSAlert     bool    `ch:"bps_alert" json:"bps_alert"`
	PPSAlert     bool    `ch:"pps_alert" json:"pps_alert"`
	FPSAlert     bool    `ch:"fps_alert" json:"fps_alert"`
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

func (s *AlertService) GetDDoSAlerts(ctx context.Context) (*[]DDoSAlert, error) {
	query := `
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
	FROM flows.advanced_ddos_alerts_vw(date=now(), sensitivity='high')
	LEFT JOIN flows.rules USING id
	`

	chCtx := clickhouse.Context(ctx)

	rows, err := s.Connection.Query(chCtx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []DDoSAlert
	for rows.Next() {
		var result DDoSAlert
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
