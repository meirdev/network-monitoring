CREATE TABLE IF NOT EXISTS flows.routers
(
    id LowCardinality(String), 
    name LowCardinality(String), 
    router_ip String, 
    default_sampling UInt64
)
ENGINE = ReplacingMergeTree()
PRIMARY KEY id;

CREATE TABLE IF NOT EXISTS flows.rules
(
    id LowCardinality(String), 
    name LowCardinality(String), 
    prefixes Array(LowCardinality(String)), 
    type Enum('threshold', 'zscore', 'advanced_ddos'), 
    bandwidth_threshold Nullable(UInt64) COMMENT 'in bits per second', 
    packet_threshold Nullable(UInt64), 
    duration Nullable(UInt64) COMMENT 'in minutes', 
    zscore_sensitivity Nullable(Enum('low', 'medium', 'high')), 
    zscore_target Nullable(Enum('bits', 'packets'))
)
ENGINE = ReplacingMergeTree()
PRIMARY KEY id;

CREATE TABLE IF NOT EXISTS flows.kafka_sink
(
    type Int32, 
    sequence_num UInt32, 
    sampling_rate UInt64, 
    sampler_address FixedString(16), 
    time_received_ns UInt64, 
    time_flow_start_ns UInt64, 
    time_flow_end_ns UInt64, 
    bytes UInt64, 
    packets UInt64, 
    src_addr FixedString(16), 
    dst_addr FixedString(16), 
    etype UInt32, 
    proto UInt32, 
    ip_tos UInt32, 
    ip_ttl UInt32, 
    ip_flags UInt32, 
    tcp_flags UInt32, 
    icmp_type UInt32, 
    icmp_code UInt32, 
    src_port UInt32, 
    dst_port UInt32, 
    src_as UInt32, 
    dst_as UInt32, 
    src_net UInt32, 
    dst_net UInt32, 
    next_hop FixedString(16), 
    next_hop_as UInt32, 
    bgp_next_hop FixedString(16), 
    in_if UInt32, 
    out_if UInt32, 
    src_mac UInt64, 
    dst_mac UInt64, 
    forwarding_status UInt32, 
    observation_domain_id UInt32, 
    observation_point_id UInt32
)
ENGINE = Kafka()
SETTINGS kafka_broker_list = 'kafka:9093', kafka_num_consumers = 1, kafka_topic_list = 'flows', kafka_group_name = 'clickhouse', kafka_format = 'Protobuf', kafka_schema = 'flow.proto:FlowMessage';

CREATE TABLE IF NOT EXISTS flows.raw
(
    type UInt8 CODEC(T64, LZ4),
    type_str LowCardinality(String) CODEC(ZSTD(1)),

    sequence_num UInt32 CODEC(T64, LZ4),
    sampling_rate UInt32 CODEC(T64, LZ4),

    sampler_address UInt128 CODEC(ZSTD(1)),
    sampler_address_str LowCardinality(String) CODEC(ZSTD(1)),

    time_received DateTime64(9) CODEC(DoubleDelta, ZSTD(1)),
    time_flow_start DateTime64(9) CODEC(DoubleDelta, ZSTD(1)),
    time_flow_end DateTime64(9) CODEC(DoubleDelta, ZSTD(1)),

    bytes UInt64 CODEC(T64, ZSTD(1)),
    total_bytes UInt64 CODEC(T64, ZSTD(1)),

    packets UInt64 CODEC(T64, ZSTD(1)),
    total_packets UInt64 CODEC(T64, ZSTD(1)),

    src_addr UInt128 CODEC(ZSTD(1)),
    src_addr_str String CODEC(ZSTD(1)),

    dst_addr UInt128 CODEC(ZSTD(1)),
    dst_addr_str String CODEC(ZSTD(1)),

    etype UInt16 CODEC(T64, LZ4),
    etype_str LowCardinality(String) CODEC(ZSTD(1)),

    proto UInt8 CODEC(T64, LZ4),
    proto_str LowCardinality(String) CODEC(ZSTD(1)),

    ip_tos UInt8 CODEC(T64, LZ4),
    ip_ttl UInt8 CODEC(T64, LZ4),
    ip_flags UInt8 CODEC(T64, LZ4),

    tcp_flags UInt16 CODEC(T64, LZ4),
    tcp_flags_str LowCardinality(String) CODEC(ZSTD(1)),

    icmp_type UInt8 CODEC(T64, LZ4),
    icmp_code UInt8 CODEC(T64, LZ4),

    src_port UInt16 CODEC(T64, LZ4),
    dst_port UInt16 CODEC(T64, LZ4),

    src_as UInt32 CODEC(T64, LZ4),
    dst_as UInt32 CODEC(T64, LZ4),

    src_net UInt8 CODEC(T64, LZ4),
    dst_net UInt8 CODEC(T64, LZ4),

    next_hop UInt128 CODEC(ZSTD(1)),
    next_hop_as UInt32 CODEC(T64, LZ4),

    bgp_next_hop UInt128 CODEC(ZSTD(1)),

    in_if UInt32 CODEC(T64, LZ4),
    out_if UInt32 CODEC(T64, LZ4),

    src_mac UInt64 CODEC(ZSTD(1)),
    dst_mac UInt64 CODEC(ZSTD(1)),

    forwarding_status UInt32 CODEC(T64, LZ4),
    forwarding_status_str LowCardinality(String) CODEC(ZSTD(1)),

    observation_domain_id UInt32 CODEC(T64, LZ4),
    observation_point_id UInt32 CODEC(T64, LZ4),

    prefixes Array(LowCardinality(String)) CODEC(ZSTD(1))
)
ENGINE = MergeTree()
PARTITION BY toDate(time_received)
ORDER BY time_received
TTL toDate(time_received) + INTERVAL 30 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_range
(
    prefix String, 
    start UInt128, 
    end UInt128
)
ENGINE = MergeTree()
ORDER BY (start, end);

CREATE TABLE IF NOT EXISTS flows.prefixes_src_1h
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    network String CODEC(ZSTD(1)),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    bytes UInt64 CODEC(Delta, ZSTD(1)),
    packets UInt64 CODEC(Delta, ZSTD(1)),
    flows UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, network, time_received)
TTL toDate(time_received) + INTERVAL 7 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_src_1d
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    network String CODEC(ZSTD(1)),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    bytes UInt64 CODEC(Delta, ZSTD(1)),
    packets UInt64 CODEC(Delta, ZSTD(1)),
    flows UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, network, time_received)
TTL toDate(time_received) + INTERVAL 90 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_ip_port_1m
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    dst_addr String CODEC(ZSTD(1)),
    dst_port UInt16 CODEC(T64, LZ4),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_bytes UInt64 CODEC(Delta, ZSTD(1)),
    any_packets UInt64 CODEC(Delta, ZSTD(1)),
    any_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_flows UInt64 CODEC(Delta, ZSTD(1)),
    udp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    udp_packets UInt64 CODEC(Delta, ZSTD(1)),
    udp_flows UInt64 CODEC(Delta, ZSTD(1)),
    gre_bytes UInt64 CODEC(Delta, ZSTD(1)),
    gre_packets UInt64 CODEC(Delta, ZSTD(1)),
    gre_flows UInt64 CODEC(Delta, ZSTD(1)),
    esp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    esp_packets UInt64 CODEC(Delta, ZSTD(1)),
    esp_flows UInt64 CODEC(Delta, ZSTD(1)),
    icmp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    icmp_packets UInt64 CODEC(Delta, ZSTD(1)),
    icmp_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_flows UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, dst_addr, dst_port, time_received)
TTL toDate(time_received) + INTERVAL 3 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_ip_port_1h
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    dst_addr String CODEC(ZSTD(1)),
    dst_port UInt16 CODEC(T64, LZ4),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_bytes UInt64 CODEC(Delta, ZSTD(1)),
    any_packets UInt64 CODEC(Delta, ZSTD(1)),
    any_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_flows UInt64 CODEC(Delta, ZSTD(1)),
    udp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    udp_packets UInt64 CODEC(Delta, ZSTD(1)),
    udp_flows UInt64 CODEC(Delta, ZSTD(1)),
    gre_bytes UInt64 CODEC(Delta, ZSTD(1)),
    gre_packets UInt64 CODEC(Delta, ZSTD(1)),
    gre_flows UInt64 CODEC(Delta, ZSTD(1)),
    esp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    esp_packets UInt64 CODEC(Delta, ZSTD(1)),
    esp_flows UInt64 CODEC(Delta, ZSTD(1)),
    icmp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    icmp_packets UInt64 CODEC(Delta, ZSTD(1)),
    icmp_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_flows UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, dst_addr, dst_port, time_received)
TTL toDate(time_received) + INTERVAL 14 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_ip_port_1d
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    dst_addr String CODEC(ZSTD(1)),
    dst_port UInt16 CODEC(T64, LZ4),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_p95_bytes UInt64 CODEC(ZSTD(1)),
    any_p95_packets UInt64 CODEC(ZSTD(1)),
    any_p95_flows UInt64 CODEC(ZSTD(1)),
    any_max_bytes UInt64 CODEC(ZSTD(1)),
    any_max_packets UInt64 CODEC(ZSTD(1)),
    any_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_max_flows UInt64 CODEC(ZSTD(1)),
    udp_p95_bytes UInt64 CODEC(ZSTD(1)),
    udp_p95_packets UInt64 CODEC(ZSTD(1)),
    udp_p95_flows UInt64 CODEC(ZSTD(1)),
    udp_max_bytes UInt64 CODEC(ZSTD(1)),
    udp_max_packets UInt64 CODEC(ZSTD(1)),
    udp_max_flows UInt64 CODEC(ZSTD(1)),
    gre_p95_bytes UInt64 CODEC(ZSTD(1)),
    gre_p95_packets UInt64 CODEC(ZSTD(1)),
    gre_p95_flows UInt64 CODEC(ZSTD(1)),
    gre_max_bytes UInt64 CODEC(ZSTD(1)),
    gre_max_packets UInt64 CODEC(ZSTD(1)),
    gre_max_flows UInt64 CODEC(ZSTD(1)),
    esp_p95_bytes UInt64 CODEC(ZSTD(1)),
    esp_p95_packets UInt64 CODEC(ZSTD(1)),
    esp_p95_flows UInt64 CODEC(ZSTD(1)),
    esp_max_bytes UInt64 CODEC(ZSTD(1)),
    esp_max_packets UInt64 CODEC(ZSTD(1)),
    esp_max_flows UInt64 CODEC(ZSTD(1)),
    icmp_p95_bytes UInt64 CODEC(ZSTD(1)),
    icmp_p95_packets UInt64 CODEC(ZSTD(1)),
    icmp_p95_flows UInt64 CODEC(ZSTD(1)),
    icmp_max_bytes UInt64 CODEC(ZSTD(1)),
    icmp_max_packets UInt64 CODEC(ZSTD(1)),
    icmp_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_flows UInt64 CODEC(ZSTD(1))
)
ENGINE = MergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, dst_addr, dst_port, time_received)
TTL toDate(time_received) + INTERVAL 90 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_ip_1m
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    dst_addr String CODEC(ZSTD(1)),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_bytes UInt64 CODEC(Delta, ZSTD(1)),
    any_packets UInt64 CODEC(Delta, ZSTD(1)),
    any_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_flows UInt64 CODEC(Delta, ZSTD(1)),
    udp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    udp_packets UInt64 CODEC(Delta, ZSTD(1)),
    udp_flows UInt64 CODEC(Delta, ZSTD(1)),
    gre_bytes UInt64 CODEC(Delta, ZSTD(1)),
    gre_packets UInt64 CODEC(Delta, ZSTD(1)),
    gre_flows UInt64 CODEC(Delta, ZSTD(1)),
    esp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    esp_packets UInt64 CODEC(Delta, ZSTD(1)),
    esp_flows UInt64 CODEC(Delta, ZSTD(1)),
    icmp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    icmp_packets UInt64 CODEC(Delta, ZSTD(1)),
    icmp_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_flows UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, dst_addr, time_received)
TTL toDate(time_received) + INTERVAL 7 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_ip_1h
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    dst_addr String CODEC(ZSTD(1)),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_bytes UInt64 CODEC(Delta, ZSTD(1)),
    any_packets UInt64 CODEC(Delta, ZSTD(1)),
    any_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_flows UInt64 CODEC(Delta, ZSTD(1)),
    udp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    udp_packets UInt64 CODEC(Delta, ZSTD(1)),
    udp_flows UInt64 CODEC(Delta, ZSTD(1)),
    gre_bytes UInt64 CODEC(Delta, ZSTD(1)),
    gre_packets UInt64 CODEC(Delta, ZSTD(1)),
    gre_flows UInt64 CODEC(Delta, ZSTD(1)),
    esp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    esp_packets UInt64 CODEC(Delta, ZSTD(1)),
    esp_flows UInt64 CODEC(Delta, ZSTD(1)),
    icmp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    icmp_packets UInt64 CODEC(Delta, ZSTD(1)),
    icmp_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_flows UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, dst_addr, time_received)
TTL toDate(time_received) + INTERVAL 30 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_ip_1d
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    dst_addr String CODEC(ZSTD(1)),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_p95_bytes UInt64 CODEC(ZSTD(1)),
    any_p95_packets UInt64 CODEC(ZSTD(1)),
    any_p95_flows UInt64 CODEC(ZSTD(1)),
    any_max_bytes UInt64 CODEC(ZSTD(1)),
    any_max_packets UInt64 CODEC(ZSTD(1)),
    any_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_max_flows UInt64 CODEC(ZSTD(1)),
    udp_p95_bytes UInt64 CODEC(ZSTD(1)),
    udp_p95_packets UInt64 CODEC(ZSTD(1)),
    udp_p95_flows UInt64 CODEC(ZSTD(1)),
    udp_max_bytes UInt64 CODEC(ZSTD(1)),
    udp_max_packets UInt64 CODEC(ZSTD(1)),
    udp_max_flows UInt64 CODEC(ZSTD(1)),
    gre_p95_bytes UInt64 CODEC(ZSTD(1)),
    gre_p95_packets UInt64 CODEC(ZSTD(1)),
    gre_p95_flows UInt64 CODEC(ZSTD(1)),
    gre_max_bytes UInt64 CODEC(ZSTD(1)),
    gre_max_packets UInt64 CODEC(ZSTD(1)),
    gre_max_flows UInt64 CODEC(ZSTD(1)),
    esp_p95_bytes UInt64 CODEC(ZSTD(1)),
    esp_p95_packets UInt64 CODEC(ZSTD(1)),
    esp_p95_flows UInt64 CODEC(ZSTD(1)),
    esp_max_bytes UInt64 CODEC(ZSTD(1)),
    esp_max_packets UInt64 CODEC(ZSTD(1)),
    esp_max_flows UInt64 CODEC(ZSTD(1)),
    icmp_p95_bytes UInt64 CODEC(ZSTD(1)),
    icmp_p95_packets UInt64 CODEC(ZSTD(1)),
    icmp_p95_flows UInt64 CODEC(ZSTD(1)),
    icmp_max_bytes UInt64 CODEC(ZSTD(1)),
    icmp_max_packets UInt64 CODEC(ZSTD(1)),
    icmp_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_flows UInt64 CODEC(ZSTD(1))
)
ENGINE = MergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, dst_addr, time_received)
TTL toDate(time_received) + INTERVAL 90 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_proto_1m
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_bytes UInt64 CODEC(Delta, ZSTD(1)),
    any_packets UInt64 CODEC(Delta, ZSTD(1)),
    any_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_flows UInt64 CODEC(Delta, ZSTD(1)),
    udp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    udp_packets UInt64 CODEC(Delta, ZSTD(1)),
    udp_flows UInt64 CODEC(Delta, ZSTD(1)),
    gre_bytes UInt64 CODEC(Delta, ZSTD(1)),
    gre_packets UInt64 CODEC(Delta, ZSTD(1)),
    gre_flows UInt64 CODEC(Delta, ZSTD(1)),
    esp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    esp_packets UInt64 CODEC(Delta, ZSTD(1)),
    esp_flows UInt64 CODEC(Delta, ZSTD(1)),
    icmp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    icmp_packets UInt64 CODEC(Delta, ZSTD(1)),
    icmp_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_flows UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, time_received)
TTL toDate(time_received) + INTERVAL 30 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_proto_1h
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_bytes UInt64 CODEC(Delta, ZSTD(1)),
    any_packets UInt64 CODEC(Delta, ZSTD(1)),
    any_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_flows UInt64 CODEC(Delta, ZSTD(1)),
    udp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    udp_packets UInt64 CODEC(Delta, ZSTD(1)),
    udp_flows UInt64 CODEC(Delta, ZSTD(1)),
    gre_bytes UInt64 CODEC(Delta, ZSTD(1)),
    gre_packets UInt64 CODEC(Delta, ZSTD(1)),
    gre_flows UInt64 CODEC(Delta, ZSTD(1)),
    esp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    esp_packets UInt64 CODEC(Delta, ZSTD(1)),
    esp_flows UInt64 CODEC(Delta, ZSTD(1)),
    icmp_bytes UInt64 CODEC(Delta, ZSTD(1)),
    icmp_packets UInt64 CODEC(Delta, ZSTD(1)),
    icmp_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_fin_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_syn_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_rst_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_psh_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_ack_flows UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_bytes UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_packets UInt64 CODEC(Delta, ZSTD(1)),
    tcp_urg_flows UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, time_received)
TTL toDate(time_received) + INTERVAL 90 DAY;

CREATE TABLE IF NOT EXISTS flows.prefixes_proto_1d
(
    prefix LowCardinality(String) CODEC(ZSTD(1)),
    time_received DateTime CODEC(DoubleDelta, LZ4),
    any_p95_bytes UInt64 CODEC(ZSTD(1)),
    any_p95_packets UInt64 CODEC(ZSTD(1)),
    any_p95_flows UInt64 CODEC(ZSTD(1)),
    any_max_bytes UInt64 CODEC(ZSTD(1)),
    any_max_packets UInt64 CODEC(ZSTD(1)),
    any_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_max_flows UInt64 CODEC(ZSTD(1)),
    udp_p95_bytes UInt64 CODEC(ZSTD(1)),
    udp_p95_packets UInt64 CODEC(ZSTD(1)),
    udp_p95_flows UInt64 CODEC(ZSTD(1)),
    udp_max_bytes UInt64 CODEC(ZSTD(1)),
    udp_max_packets UInt64 CODEC(ZSTD(1)),
    udp_max_flows UInt64 CODEC(ZSTD(1)),
    gre_p95_bytes UInt64 CODEC(ZSTD(1)),
    gre_p95_packets UInt64 CODEC(ZSTD(1)),
    gre_p95_flows UInt64 CODEC(ZSTD(1)),
    gre_max_bytes UInt64 CODEC(ZSTD(1)),
    gre_max_packets UInt64 CODEC(ZSTD(1)),
    gre_max_flows UInt64 CODEC(ZSTD(1)),
    esp_p95_bytes UInt64 CODEC(ZSTD(1)),
    esp_p95_packets UInt64 CODEC(ZSTD(1)),
    esp_p95_flows UInt64 CODEC(ZSTD(1)),
    esp_max_bytes UInt64 CODEC(ZSTD(1)),
    esp_max_packets UInt64 CODEC(ZSTD(1)),
    esp_max_flows UInt64 CODEC(ZSTD(1)),
    icmp_p95_bytes UInt64 CODEC(ZSTD(1)),
    icmp_p95_packets UInt64 CODEC(ZSTD(1)),
    icmp_p95_flows UInt64 CODEC(ZSTD(1)),
    icmp_max_bytes UInt64 CODEC(ZSTD(1)),
    icmp_max_packets UInt64 CODEC(ZSTD(1)),
    icmp_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_fin_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_fin_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_syn_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_syn_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_rst_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_rst_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_psh_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_psh_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_ack_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_ack_max_flows UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_bytes UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_packets UInt64 CODEC(ZSTD(1)),
    tcp_urg_p95_flows UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_bytes UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_packets UInt64 CODEC(ZSTD(1)),
    tcp_urg_max_flows UInt64 CODEC(ZSTD(1))
)
ENGINE = MergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, time_received)
TTL toDate(time_received) + INTERVAL 90 DAY;

CREATE TABLE IF NOT EXISTS flows.expressions
(
    id LowCardinality(String), 
    name LowCardinality(String), 
    expression String
)
ENGINE = ReplacingMergeTree()
PRIMARY KEY id;

CREATE TABLE IF NOT EXISTS flows.expression_metrics
(
    time_received DateTime CODEC(DoubleDelta, LZ4),
    expression_id LowCardinality(String) CODEC(ZSTD(1)),
    packets UInt64 CODEC(Delta, ZSTD(1)),
    bytes UInt64 CODEC(Delta, ZSTD(1))
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (expression_id, time_received)
TTL toDate(time_received) + INTERVAL 30 DAY;

CREATE TABLE IF NOT EXISTS flows.expression_metrics_1m AS flows.expression_metrics;
