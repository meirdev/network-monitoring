package services

import (
	"context"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
	"github.com/meirdev/network-monitoring/api/common"
)

type Rule struct {
	Id                 string   `ch:"id" json:"id"`
	Name               string   `ch:"name" json:"name" binding:"required,max=256"`
	Prefixes           []string `ch:"prefixes" json:"prefixes" binding:"required,dive,cidr"`
	Type               string   `ch:"type" json:"type" binding:"required,oneof=threshold zscore advanced_ddos"`
	BandwidthThreshold *uint64  `ch:"bandwidth_threshold" json:"bandwidth_threshold" binding:"omitempty,min=1"`
	PacketThreshold    *uint64  `ch:"packet_threshold" json:"packet_threshold" binding:"omitempty,min=1"`
	Duration           *uint64  `ch:"duration" json:"duration" binding:"omitempty,min=1,required_if=type threshold"`
	ZScoreSensitivity  *string  `ch:"zscore_sensitivity" json:"zscore_sensitivity" binding:"omitempty,oneof=low medium high,required_if=type zscore"`
	ZScoreTarget       *string  `ch:"zscore_target" json:"zscore_target" binding:"omitempty,oneof=bits packets,required_if=type zscore"`
}

type RuleService struct {
	Connection driver.Conn
}

func NewRuleService(conn driver.Conn) *RuleService {
	return &RuleService{
		Connection: conn,
	}
}

func (s *RuleService) GetRules(ctx context.Context) (*[]Rule, error) {
	rows, err := s.Connection.Query(
		ctx,
		"SELECT id, name, prefixes, type, bandwidth_threshold, packet_threshold, duration, zscore_sensitivity, zscore_target FROM flows.rules",
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var rules []Rule
	for rows.Next() {
		var rule Rule
		if err := rows.ScanStruct(&rule); err != nil {
			return nil, err
		}
		rules = append(rules, rule)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &rules, nil
}

func (s *RuleService) GetRule(ctx context.Context, id string) (*Rule, error) {
	var rule Rule
	row := s.Connection.QueryRow(
		ctx,
		"SELECT id, name, prefixes, type, bandwidth_threshold, packet_threshold, duration, zscore_sensitivity, zscore_target FROM flows.rules WHERE id = @id",
		clickhouse.Named("id", id),
	)
	if err := row.ScanStruct(&rule); err != nil {
		return nil, err
	}

	return &rule, nil
}

func (s *RuleService) AddRule(ctx context.Context, rule Rule) (*string, error) {
	id := common.GenerateId()

	if err := s.Connection.Exec(
		ctx,
		"INSERT INTO flows.rules (id, name, prefixes, type, bandwidth_threshold, packet_threshold, duration, zscore_sensitivity, zscore_target) VALUES (@id, @name, @prefixes, @type, @bandwidth_threshold, @packet_threshold, @duration, @zscore_sensitivity, @zscore_target)",
		clickhouse.Named("id", id),
		clickhouse.Named("name", rule.Name),
		clickhouse.Named("prefixes", rule.Prefixes),
		clickhouse.Named("type", rule.Type),
		clickhouse.Named("bandwidth_threshold", rule.BandwidthThreshold),
		clickhouse.Named("packet_threshold", rule.PacketThreshold),
		clickhouse.Named("duration", rule.Duration),
		clickhouse.Named("zscore_sensitivity", rule.ZScoreSensitivity),
		clickhouse.Named("zscore_target", rule.ZScoreTarget),
	); err != nil {
		return nil, err
	}

	if err := s.updateDictionary(ctx); err != nil {
		return nil, err
	}

	return &id, nil
}

func (s *RuleService) UpdateRule(ctx context.Context, rule Rule) error {
	if err := s.Connection.Exec(
		ctx,
		"ALTER TABLE flows.rules UPDATE name = @name, prefixes = @prefixes, type = @type, bandwidth_threshold = @bandwidth_threshold, packet_threshold = @packet_threshold, duration = @duration, zscore_sensitivity = @zscore_sensitivity, zscore_target = @zscore_target WHERE id = @id",
		clickhouse.Named("id", rule.Id),
		clickhouse.Named("name", rule.Name),
		clickhouse.Named("prefixes", rule.Prefixes),
		clickhouse.Named("type", rule.Type),
		clickhouse.Named("bandwidth_threshold", rule.BandwidthThreshold),
		clickhouse.Named("packet_threshold", rule.PacketThreshold),
		clickhouse.Named("duration", rule.Duration),
		clickhouse.Named("zscore_sensitivity", rule.ZScoreSensitivity),
		clickhouse.Named("zscore_target", rule.ZScoreTarget),
	); err != nil {
		return err
	}

	if err := s.updateDictionary(ctx); err != nil {
		return err
	}

	return nil
}

func (s *RuleService) DeleteRule(ctx context.Context, rule_id string) error {
	if err := s.Connection.Exec(
		ctx,
		"ALTER TABLE flows.rules DELETE WHERE id = @rule_id",
		clickhouse.Named("rule_id", rule_id),
	); err != nil {
		return err
	}

	if err := s.updateDictionary(ctx); err != nil {
		return err
	}

	return nil
}

func (s *RuleService) updateDictionary(ctx context.Context) error {
	if err := s.Connection.Exec(
		ctx,
		"SYSTEM RELOAD DICTIONARY flows.prefixes",
	); err != nil {
		return err
	}

	return nil
}
