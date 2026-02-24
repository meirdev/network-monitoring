package db

import (
	"context"
	"fmt"
	"net/url"
	"time"

	"github.com/ClickHouse/ch-go"
	"github.com/ClickHouse/ch-go/proto"
)

type Client struct {
	conn *ch.Client
}

type Metric struct {
	TimeReceived time.Time
	ExpressionID string
	Packets      uint64
	Bytes        uint64
}

func NewClient(ctx context.Context, dsn string) (*Client, error) {
	u, err := url.Parse(dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to parse DSN: %w", err)
	}

	password, _ := u.User.Password()

	conn, err := ch.Dial(ctx, ch.Options{
		Address:  u.Host,
		Database: u.Path[1:], // Remove leading slash
		User:     u.User.Username(),
		Password: password,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to ClickHouse: %w", err)
	}

	return &Client{conn: conn}, nil
}

func (c *Client) Close() error {
	return c.conn.Close()
}

func (c *Client) InsertMetrics(ctx context.Context, metrics []Metric) error {
	if len(metrics) == 0 {
		return nil
	}

	var (
		colTimeReceived proto.ColDateTime
		colExpressionID proto.ColStr
		colPackets      proto.ColUInt64
		colBytes        proto.ColUInt64
	)

	for _, m := range metrics {
		colTimeReceived.Append(m.TimeReceived)
		colExpressionID.Append(m.ExpressionID)
		colPackets.Append(m.Packets)
		colBytes.Append(m.Bytes)
	}

	input := proto.Input{
		{Name: "time_received", Data: colTimeReceived},
		{Name: "expression_id", Data: colExpressionID},
		{Name: "packets", Data: colPackets},
		{Name: "bytes", Data: colBytes},
	}

	return c.conn.Do(ctx, ch.Query{
		Body:  "INSERT INTO flows.expression_metrics SETTINGS async_insert=1, wait_for_async_insert=0 VALUES",
		Input: input,
	})
}
