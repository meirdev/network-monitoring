package main

import (
	"context"
	"log/slog"
	"net/netip"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/network-monitoring/metrics/internal/config"
	"github.com/network-monitoring/metrics/internal/db"
	"github.com/network-monitoring/metrics/internal/expr"
	"github.com/network-monitoring/metrics/internal/flow"
	"github.com/network-monitoring/metrics/internal/kafka"
)

func main() {
	cfg := config.Parse()

	level := slog.LevelInfo
	if cfg.Debug {
		level = slog.LevelDebug
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level})))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		slog.Info("Shutting down...")
		cancel()
	}()

	chClient, err := db.NewClient(ctx, cfg.ClickHouseDSN)
	if err != nil {
		slog.Error("Failed to connect to ClickHouse", "error", err)
		os.Exit(1)
	}
	defer chClient.Close()

	consumer, err := kafka.NewConsumer(cfg.KafkaBrokers, cfg.KafkaTopic, cfg.KafkaGroup)
	if err != nil {
		slog.Error("Failed to create Kafka consumer", "error", err)
		os.Exit(1)
	}
	defer consumer.Close()

	var mu sync.RWMutex
	var compiledExprs []*expr.CompiledExpression
	var routerMap map[netip.Addr]*db.Router

	if err := refreshState(ctx, chClient, &mu, &compiledExprs, &routerMap); err != nil {
		slog.Error("Failed to load initial state", "error", err)
		os.Exit(1)
	}

	go func() {
		ticker := time.NewTicker(cfg.RefreshInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if err := refreshState(ctx, chClient, &mu, &compiledExprs, &routerMap); err != nil {
					slog.Error("Failed to refresh state", "error", err)
				}
			}
		}
	}()

	slog.Info("Starting metrics processor", "refresh_interval", cfg.RefreshInterval)

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		flows, err := consumer.Poll(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			slog.Error("Failed to poll Kafka", "error", err)
			continue
		}

		if len(flows) == 0 {
			continue
		}

		slog.Debug("Received flows from Kafka", "count", len(flows))

		mu.RLock()
		exprs := compiledExprs
		routers := routerMap
		mu.RUnlock()

		if len(exprs) == 0 {
			continue
		}

		var metrics []db.Metric

		for _, msg := range flows {
			var defaultSampling uint64
			if routers != nil {
				if router, ok := routers[db.BytesToAddr(msg.SamplerAddress)]; ok {
					defaultSampling = router.DefaultSampling
				}
			}

			slog.Debug("Raw message", "src_addr", msg.SrcAddr, "src_len", len(msg.SrcAddr),
				"dst_addr", msg.DstAddr, "dst_len", len(msg.DstAddr))

			f := flow.FromProto(msg, defaultSampling)

			slog.Debug("Flow", "src", f.SrcAddr, "src_port", f.SrcPort,
				"dst", f.DstAddr, "dst_port", f.DstPort,
				"proto", f.Proto, "bytes", f.TotalBytes, "packets", f.TotalPackets)

			for _, e := range exprs {
				match, err := e.Evaluate(&f.Flow)
				if err != nil {
					slog.Debug("Expression evaluation error", "name", e.Name, "error", err)
					continue
				}

				if match {
					slog.Debug("Expression matched", "name", e.Name, "id", e.ID,
						"src", f.SrcAddr, "src_port", f.SrcPort, "dst", f.DstAddr, "dst_port", f.DstPort)
					metrics = append(metrics, db.Metric{
						TimeReceived: f.TimeReceived,
						ExpressionID: e.ID,
						Packets:      f.TotalPackets,
						Bytes:        f.TotalBytes,
					})
				}
			}
		}

		if len(metrics) > 0 {
			if err := chClient.InsertMetrics(ctx, metrics); err != nil {
				slog.Error("Failed to insert metrics", "error", err)
			}
		}
	}
}

func refreshState(
	ctx context.Context,
	client *db.Client,
	mu *sync.RWMutex,
	compiledExprs *[]*expr.CompiledExpression,
	routerMap *map[netip.Addr]*db.Router,
) error {
	expressions, err := client.GetExpressions(ctx)
	if err != nil {
		return err
	}

	var newExprs []*expr.CompiledExpression
	for _, e := range expressions {
		compiled, err := expr.CompileWithFunctions(e.ID, e.Name, e.Expression)
		if err != nil {
			slog.Warn("Failed to compile expression", "id", e.ID, "error", err)
			continue
		}
		newExprs = append(newExprs, compiled)
	}

	routers, err := client.GetRouters(ctx)
	if err != nil {
		return err
	}
	newRouterMap := db.RouterMap(routers)

	mu.Lock()
	*compiledExprs = newExprs
	*routerMap = newRouterMap
	mu.Unlock()

	slog.Info("Loaded state", "expressions", len(newExprs), "routers", len(routers))

	return nil
}
