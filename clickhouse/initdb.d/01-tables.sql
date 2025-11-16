CREATE DATABASE IF NOT EXISTS flows;


CREATE TABLE IF NOT EXISTS flows.config (
    name LowCardinality(String),
    router_ip LowCardinality(String),
    default_sampling UInt64
)
ENGINE = ReplacingMergeTree()
PRIMARY KEY router_ip;


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


CREATE TABLE IF NOT EXISTS flows.raw AS flows.kafka_sink
ENGINE = MergeTree()
PARTITION BY toDate(toDateTime64(time_received_ns/1000000000, 9))
ORDER BY time_received_ns
TTL toDate(toDateTime64(time_received_ns/1000000000, 9)) + INTERVAL 30 DAY;


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.raw_mv TO flows.raw AS
    SELECT * FROM flows.kafka_sink;
