package services

import (
	"context"
	"fmt"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
)

type TopAggregation struct {
	Column string `ch:"column"`
	Agg    uint64 `ch:"agg"`
}

type DashboardService struct {
	Connection driver.Conn
}

func NewDashboardService(conn driver.Conn) *DashboardService {
	return &DashboardService{
		Connection: conn,
	}
}

func (s *DashboardService) GetKTop(ctx context.Context, column string, k *int, agg string) (*[]TopAggregation, error) {
	var query string

	if k == nil {
		k = &[]int{0}[0]
		query = `
		WITH top AS (
			SELECT {column:Identifier} AS column, sum({agg:Identifier}) AS agg
			FROM flows.raw
			GROUP BY column
			ORDER BY agg DESC
		)
		SELECT toString(column) AS column, agg
		FROM top
		`
	} else {
		query = `
		WITH top_k AS (
			SELECT arrayJoin(approx_top_sum({k:UInt32})({column:Identifier}, {agg:Identifier})) AS i
			FROM flows.raw
		)
		SELECT toString(i.1) AS column, i.2 AS agg
		FROM top_k
		`
	}

	chCtx := clickhouse.Context(ctx, clickhouse.WithParameters(clickhouse.Parameters{
		"column": column,
		"k":      fmt.Sprintf("%d", *k),
		"agg":    agg,
	}))

	rows, err := s.Connection.Query(chCtx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []TopAggregation
	for rows.Next() {
		var result TopAggregation
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
