package db

import (
	"context"
	"fmt"
	"net/netip"

	"github.com/ClickHouse/ch-go"
	"github.com/ClickHouse/ch-go/proto"
)

type Router struct {
	ID              string
	Name            string
	RouterIP        netip.Addr
	DefaultSampling uint64
}

func (c *Client) GetRouters(ctx context.Context) ([]Router, error) {
	var (
		colID              = new(proto.ColStr).LowCardinality()
		colName            = new(proto.ColStr).LowCardinality()
		colRouterIP        proto.ColStr
		colDefaultSampling proto.ColUInt64
	)

	var routers []Router

	if err := c.conn.Do(ctx, ch.Query{
		Body: "SELECT id, name, router_ip, default_sampling FROM flows.routers FINAL",
		Result: proto.Results{
			{Name: "id", Data: colID},
			{Name: "name", Data: colName},
			{Name: "router_ip", Data: &colRouterIP},
			{Name: "default_sampling", Data: &colDefaultSampling},
		},
		OnResult: func(ctx context.Context, block proto.Block) error {
			for i := 0; i < block.Rows; i++ {
				ip, _ := netip.ParseAddr(colRouterIP.Row(i))
				routers = append(routers, Router{
					ID:              colID.Row(i),
					Name:            colName.Row(i),
					RouterIP:        ip,
					DefaultSampling: colDefaultSampling.Row(i),
				})
			}
			return nil
		},
	}); err != nil {
		return nil, fmt.Errorf("failed to query routers: %w", err)
	}

	return routers, nil
}

func BytesToAddr(b []byte) netip.Addr {
	addr, _ := netip.AddrFromSlice(b)
	return addr.Unmap()
}

func RouterMap(routers []Router) map[netip.Addr]*Router {
	m := make(map[netip.Addr]*Router, len(routers))
	for i := range routers {
		m[routers[i].RouterIP] = &routers[i]
	}
	return m
}
