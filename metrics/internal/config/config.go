package config

import (
	"flag"
	"time"
)

type Config struct {
	KafkaBrokers    string
	KafkaTopic      string
	KafkaGroup      string
	ClickHouseDSN   string
	RefreshInterval time.Duration
	Debug           bool
}

func Parse() *Config {
	cfg := &Config{}

	flag.StringVar(&cfg.KafkaBrokers, "kafka-brokers", "kafka:9093", "Kafka broker addresses (comma-separated)")
	flag.StringVar(&cfg.KafkaTopic, "kafka-topic", "flows", "Kafka topic to consume flows from")
	flag.StringVar(&cfg.KafkaGroup, "kafka-group", "metrics", "Kafka consumer group")
	flag.StringVar(&cfg.ClickHouseDSN, "clickhouse-dsn", "clickhouse://default:password@db:9000/flows", "ClickHouse DSN")
	flag.DurationVar(&cfg.RefreshInterval, "refresh-interval", 60*time.Second, "Interval to refresh expressions and routers from database")
	flag.BoolVar(&cfg.Debug, "debug", false, "Enable debug logging")

	flag.Parse()

	return cfg
}
