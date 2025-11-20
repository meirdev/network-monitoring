package services

import (
	"context"
	"errors"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
	"github.com/meirdev/network-monitoring/api/common"
)

type Router struct {
	Id              string `ch:"id" json:"id"`
	Name            string `ch:"name" json:"name" binding:"required"`
	RouterIP        string `ch:"router_ip" json:"router_ip" binding:"required"`
	DefaultSampling uint64 `ch:"default_sampling" json:"default_sampling" binding:"required"`
}

type RouterService struct {
	Connection driver.Conn
}

func NewRouterService(conn driver.Conn) *RouterService {
	return &RouterService{
		Connection: conn,
	}
}

func (s *RouterService) GetRouters(ctx context.Context) (*[]Router, error) {
	rows, err := s.Connection.Query(ctx, "SELECT id, name, router_ip, default_sampling FROM flows.routers")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	routers := []Router{}
	for rows.Next() {
		var cfg Router
		if err := rows.ScanStruct(&cfg); err != nil {
			return nil, err
		}
		routers = append(routers, cfg)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &routers, nil
}

func (s *RouterService) GetRouter(ctx context.Context, id string) (*Router, error) {
	var router Router
	row := s.Connection.QueryRow(
		ctx,
		"SELECT id, name, router_ip, default_sampling FROM flows.routers WHERE id = @id",
		clickhouse.Named("id", id),
	)
	if err := row.ScanStruct(&router); err != nil {
		return nil, err
	}

	return &router, nil
}

func (s *RouterService) AddRouter(ctx context.Context, router Router) (*string, error) {
	var exists bool
	row := s.Connection.QueryRow(
		ctx,
		"SELECT COUNT() > 0 FROM flows.routers WHERE router_ip = @router_ip",
		clickhouse.Named("router_ip", router.RouterIP),
	)
	if err := row.Scan(&exists); err != nil {
		return nil, err
	}
	if exists {
		return nil, errors.New("router IP already exists")
	}

	id := common.GenerateId()

	if err := s.Connection.Exec(
		ctx,
		"INSERT INTO flows.routers (id, name, router_ip, default_sampling) VALUES (@id, @name, @router_ip, @default_sampling)",
		clickhouse.Named("id", id),
		clickhouse.Named("name", router.Name),
		clickhouse.Named("router_ip", router.RouterIP),
		clickhouse.Named("default_sampling", router.DefaultSampling),
	); err != nil {
		return nil, err
	}

	return &id, nil
}

func (s *RouterService) UpdateRouter(ctx context.Context, router Router) error {
	var exists bool
	row := s.Connection.QueryRow(
		ctx,
		"SELECT COUNT() > 0 FROM flows.routers WHERE router_ip = @router_ip AND id != @id",
		clickhouse.Named("router_ip", router.RouterIP),
		clickhouse.Named("id", router.Id),
	)
	if err := row.Scan(&exists); err != nil {
		return err
	}
	if exists {
		return errors.New("router IP already exists")
	}

	if err := s.Connection.Exec(
		ctx,
		"ALTER TABLE flows.routers UPDATE name = @name, router_ip = @router_ip, default_sampling = @default_sampling WHERE id = @id",
		clickhouse.Named("id", router.Id),
		clickhouse.Named("name", router.Name),
		clickhouse.Named("router_ip", router.RouterIP),
		clickhouse.Named("default_sampling", router.DefaultSampling),
	); err != nil {
		return err
	}

	return nil
}

func (s *RouterService) DeleteRouter(ctx context.Context, router_id string) error {
	if err := s.Connection.Exec(
		ctx,
		"ALTER TABLE flows.routers DELETE WHERE id = @router_id",
		clickhouse.Named("router_id", router_id),
	); err != nil {
		return err
	}

	return nil
}
