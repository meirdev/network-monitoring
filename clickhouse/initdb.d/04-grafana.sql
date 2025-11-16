CREATE TABLE IF NOT EXISTS flows.grafana
(
    sampler_address LowCardinality(String),

    time_received DateTime64(9),
    time_flow_start DateTime64(9),
    time_flow_end DateTime64(9),

    bytes UInt64,
    packets UInt64,

    src_addr String,
    dst_addr String,

    etype LowCardinality(String),

    proto LowCardinality(String),

    tcp_flags LowCardinality(String),

    src_port UInt16,
    dst_port UInt16,

    forwarding_status LowCardinality(String)
)
ENGINE = MergeTree()
PARTITION BY toDate(time_received)
ORDER BY time_received
TTL toDate(time_received) + INTERVAL 30 DAY;


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.grafana_mv TO flows.grafana AS
    SELECT
        BytesToIPString(sampler_address) AS sampler_address,

        toDateTime64(time_received_ns/1000000000, 9) AS time_received,
        toDateTime64(time_flow_start_ns/1000000000, 9) AS time_flow_start,
        toDateTime64(time_flow_end_ns/1000000000, 9) AS time_flow_end,

        bytes * if(flows.config.default_sampling = 0, sampling_rate, flows.config.default_sampling) AS bytes,
        packets * if(flows.config.default_sampling = 0, sampling_rate, flows.config.default_sampling) AS packets,

        BytesToIPString(src_addr) AS src_addr,
        BytesToIPString(dst_addr) AS dst_addr,

        NumToETypeString(etype) AS etype,

        NumToProtoString(proto) AS proto,

        NumToTcpFlagsString(tcp_flags) AS tcp_flags,

        src_port,
        dst_port,

        -- Fix for Juniper devices with `report-zero-oif-gw-on-discard` enabled:
        NumToForwardingStatusString(if(empty(next_hop) = 1 AND out_if = 0, 2, forwarding_status)) AS forwarding_status
    FROM flows.raw
    LEFT JOIN flows.config FINAL ON sampler_address == flows.config.router_ip;
