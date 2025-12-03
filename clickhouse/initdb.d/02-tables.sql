CREATE TABLE IF NOT EXISTS flows.routers (
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
    type Enum('threshold', 'zscore'),
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
SETTINGS
    kafka_broker_list = 'kafka:9093',
    kafka_num_consumers = 1,
    kafka_topic_list = 'flows',
    kafka_group_name = 'clickhouse',
    kafka_format = 'Protobuf',
    kafka_schema = 'flow.proto:FlowMessage';


CREATE TABLE IF NOT EXISTS flows.raw
(
    type Int32,

    sequence_num UInt32,
    sampling_rate UInt64,
    sampler_address FixedString(16),

    time_received DateTime64(9),
    time_flow_start DateTime64(9),
    time_flow_end DateTime64(9),

    bytes UInt64,
    packets UInt64,

    src_addr FixedString(16),
    dst_addr FixedString(16),

    etype UInt16,
    proto UInt8,

    tcp_flags UInt32,

    icmp_type UInt32,
    icmp_code UInt32,

    src_port UInt16,
    dst_port UInt16,

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
    observation_point_id UInt32,

    sampler_address_str LowCardinality(String),
    total_bytes UInt64,
    total_packets UInt64,
    src_addr_str String,
    dst_addr_str String,
    etype_str LowCardinality(String),
    proto_str LowCardinality(String),
    tcp_flags_str LowCardinality(String),
    forwarding_status_str LowCardinality(String),
    prefixes Array(LowCardinality(String))
)
ENGINE = MergeTree()
PARTITION BY toDate(time_received)
ORDER BY time_received
TTL toDate(time_received) + INTERVAL 30 DAY;


CREATE TABLE IF NOT EXISTS flows.prefixes_total_1m
(
    prefix LowCardinality(String),

    time_received DateTime,

    bytes UInt64,
    packets UInt64,
    flows UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, time_received)
TTL toDate(time_received) + INTERVAL 30 DAY;


-- The IP_TRIE layout of the dictionary did not allow us to get all the prefixes that match a given IP address.
-- Example: If we have prefixes of '10.0.0.0/8' and '10.0.0/16', and we query for '10.0.0.1', we will only get the most specific prefix '10.0.0/16'.
-- If it's really necessary, we can create a table with prefixes and use it instead of the dictionary.

-- We convert the prefixes to ranges so that we can speed up the search for matching prefixes.

CREATE TABLE IF NOT EXISTS flows.prefixes_range (
    prefix String,
    start UInt128,
    end UInt128
)
ENGINE = MergeTree()
ORDER BY (start, end);


CREATE TABLE IF NOT EXISTS flows.prefixes_src_profile_10m
(
    prefix LowCardinality(String),

    network String CODEC(ZSTD(6)),

    time_received DateTime,

    bytes UInt64,
    packets UInt64,
    flows UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, network, time_received)
TTL toDate(time_received) + INTERVAL 7 DAY;


CREATE TABLE IF NOT EXISTS flows.prefixes_dst_profile_10m
(
    prefix LowCardinality(String),

    time_received DateTime,

    protoMap Nested(
        proto UInt8,
        bytes UInt64,
        packets UInt64,
        flows UInt64
    ),

    tcpFlagMap Nested(
        tcp_flag UInt16,
        bytes UInt64,
        packets UInt64,
        flows UInt64
    ),

    bytes UInt64,
    packets UInt64,
    flows UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, `protoMap.proto`, `tcpFlagMap.tcp_flag`, time_received)
TTL toDate(time_received) + INTERVAL 7 DAY;
