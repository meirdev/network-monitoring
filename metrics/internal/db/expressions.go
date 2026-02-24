package db

import (
	"context"
	"fmt"

	"github.com/ClickHouse/ch-go"
	"github.com/ClickHouse/ch-go/proto"
)

type Expression struct {
	ID         string
	Name       string
	Expression string
}

func (c *Client) GetExpressions(ctx context.Context) ([]Expression, error) {
	var (
		colID         = new(proto.ColStr).LowCardinality()
		colName       = new(proto.ColStr).LowCardinality()
		colExpression proto.ColStr
	)

	var expressions []Expression

	if err := c.conn.Do(ctx, ch.Query{
		Body: "SELECT id, name, expression FROM flows.expressions FINAL",
		Result: proto.Results{
			{Name: "id", Data: colID},
			{Name: "name", Data: colName},
			{Name: "expression", Data: &colExpression},
		},
		OnResult: func(ctx context.Context, block proto.Block) error {
			for i := 0; i < block.Rows; i++ {
				expressions = append(expressions, Expression{
					ID:         colID.Row(i),
					Name:       colName.Row(i),
					Expression: colExpression.Row(i),
				})
			}
			return nil
		},
	}); err != nil {
		return nil, fmt.Errorf("failed to query expressions: %w", err)
	}

	return expressions, nil
}
