CREATE TABLE IF NOT EXISTS flows
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

    src_port UInt32,
    dst_port UInt32,

    src_as UInt32,
    dst_as UInt32,

    next_hop FixedString(16),
    next_hop_as UInt32,

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

CREATE TABLE IF NOT EXISTS routers (
    name LowCardinality(String),
    router_ip LowCardinality(String),
    default_sampling UInt64
)
ENGINE = ReplacingMergeTree()
PRIMARY KEY router_ip;

CREATE TABLE IF NOT EXISTS prefixes (
    name LowCardinality(String),
    prefix LowCardinality(String)
)
ENGINE = ReplacingMergeTree()
PRIMARY KEY prefix;

CREATE DATABASE IF NOT EXISTS dictionaries;

CREATE DICTIONARY IF NOT EXISTS dictionaries.protocols (
    proto UInt8,
    name String,
    description String
)
PRIMARY KEY proto
LAYOUT(FLAT())
SOURCE (FILE(path '/var/lib/clickhouse/user_files/protocols.csv' format 'CSVWithNames'))
LIFETIME(0);

CREATE DICTIONARY IF NOT EXISTS dictionaries.routers (
    name String,
    router_ip String,
    default_sampling UInt64
)
PRIMARY KEY router_ip
LAYOUT(HASHED())
SOURCE (CLICKHOUSE(query 'SELECT name, router_ip, default_sampling FROM routers FINAL' user 'default' password 'password'))
LIFETIME(360);

CREATE DICTIONARY IF NOT EXISTS dictionaries.prefixes (
    key String,
    prefix String
)
PRIMARY KEY key
LAYOUT(IP_TRIE)
SOURCE (CLICKHOUSE(query 'SELECT prefix AS key, prefix FROM prefixes FINAL' user 'default' password 'password'))
LIFETIME(360);


-- The IP_TRIE layout of the dictionary did not allow us to get all the prefixes that match a given IP address.
-- Example: If we have prefixes of '10.0.0.0/8' and '10.0.0/16', and we query for '10.0.0.1', we will only get the most specific prefix '10.0.0/16'.
-- If it's really necessary, we can create a table with prefixes and use it instead of the dictionary:

CREATE TABLE IF NOT EXISTS prefixes_range (
    prefix String,
    start UInt128,
    end UInt128
)
ENGINE = MergeTree()
ORDER BY (start, end);

CREATE FUNCTION IF NOT EXISTS ipToNum AS (ip) ->
(
    if(position(ip, '.') <> 0, toUInt128(IPv4StringToNum(ip)), toUInt128(IPv6StringToNum(ip)))
);

-- We convert the prefixes to ranges so that we can speed up the search for matching prefixes.

CREATE MATERIALIZED VIEW IF NOT EXISTS prefixes_range_mv TO prefixes_range AS
    WITH split_prefix AS (
        SELECT
            prefix,
            splitByChar('/', prefix) AS ip_mask,
            ip_mask[1] AS ip,
            toUInt8(ip_mask[2]) AS mask
        FROM prefixes
    ),
    ipv4_prefixes AS (
        SELECT
            prefix,
            IPv4CIDRToRange(IPv4StringToNum(ip), mask) AS ip_range
        FROM split_prefix
        WHERE position(ip, '.') <> 0
    ),
    ipv6_prefixes AS (
        SELECT
            prefix,
            IPv6CIDRToRange(IPv6StringToNum(ip), mask) AS ip_range
        FROM split_prefix
        WHERE position(ip, '.') = 0
    )
    SELECT prefix, toUInt128(ip_range.1) AS start, toUInt128(ip_range.2) AS end FROM ipv4_prefixes
    UNION ALL
    SELECT prefix, toUInt128(ip_range.1) AS start, toUInt128(ip_range.2) AS end FROM ipv6_prefixes
    ORDER BY start, end;

-- Usage example:

-- WITH ipToNum('10.0.0.1') AS ip SELECT prefix FROM prefixes_range WHERE ip BETWEEN start AND end;


CREATE FUNCTION IF NOT EXISTS convertFixedStringIpToString AS (addr) ->
(
    -- if the first 12 bytes are zero, then it's an IPv4 address, otherwise it's an IPv6 address
    if(reinterpretAsUInt128(substring(reverse(addr), 1, 12)) = 0, IPv4NumToString(reinterpretAsUInt32(substring(reverse(addr), 13, 4))), IPv6NumToString(addr))
);

CREATE FUNCTION IF NOT EXISTS convertFlowTypeToString AS (type) ->
(
    transform(type, [0, 1, 2, 3, 4], ['UNKNOWN', 'SFLOW_5', 'NETFLOW_V5', 'NETFLOW_V9', 'IPFIX'], toString(type))
);

CREATE FUNCTION IF NOT EXISTS convertFlowETypeToString AS (etype) ->
(
    transform(etype, [0x800, 0x806, 0x86dd], ['IPv4', 'ARP', 'IPv6'], toString(etype))
);

CREATE FUNCTION IF NOT EXISTS convertFlowTcpFlagsToString AS (tcp_flags) ->
(
    if(tcp_flags = 0, 'EMPTY', arrayStringConcat(arrayMap(x -> transform(x, [1, 2, 4, 8, 16, 32, 64, 128, 256, 512], ['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECN', 'CWR', 'NONCE', 'RESERVED'], toString(x)), bitmaskToArray(tcp_flags)), '+'))
);

CREATE FUNCTION IF NOT EXISTS convertFlowForwardingStatusToString AS (forwarding_status) ->
(
    transform(forwarding_status, [0, 1, 2, 3], ['UNKNOWN', 'FORWARDED', 'DROPPED', 'CONSUMED'], toString(forwarding_status))
);

-- We store the string representations of the fields in the flows_raw table to avoid unnecessary calculations during queries.

CREATE TABLE IF NOT EXISTS flows_raw
(
    type Int32,
    type_string LowCardinality(String) MATERIALIZED convertFlowTypeToString(type),

    sequence_num UInt32,
    sampler_address LowCardinality(String),

    time_received DateTime64(9),
    time_flow_start DateTime64(9),
    time_flow_end DateTime64(9),

    bytes UInt64,
    packets UInt64,

    src_addr String,
    dst_addr String,

    etype UInt16,
    etype_string LowCardinality(String) MATERIALIZED convertFlowETypeToString(etype),

    proto UInt8,
    proto_string LowCardinality(String) MATERIALIZED dictGetOrDefault('dictionaries.protocols', 'name', proto, toString(proto)),

    tcp_flags UInt16,
    tcp_flags_string LowCardinality(String) MATERIALIZED convertFlowTcpFlagsToString(tcp_flags),

    src_port UInt16,
    dst_port UInt16,

    src_as UInt32,
    dst_as UInt32,

    next_hop String,
    next_hop_as UInt32,

    in_if UInt32,
    out_if UInt32,

    src_mac String,
    dst_mac String,

    forwarding_status UInt32,
    forwarding_status_string LowCardinality(String) MATERIALIZED convertFlowForwardingStatusToString(forwarding_status),

    observation_domain_id UInt32,
    observation_point_id UInt32
)
ENGINE = MergeTree()
PARTITION BY toDate(time_flow_start)
ORDER BY time_flow_start
TTL toDate(time_flow_start) + INTERVAL 30 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows_raw_mv TO flows_raw AS
    WITH temp AS (
        SELECT
            type,

            convertFixedStringIpToString(sampler_address) AS sampler_address_string,

            sequence_num,
            dictGetOrDefault('dictionaries.routers', 'default_sampling', sampler_address_string, sampling_rate) AS default_sampling_rate,

            toDateTime64(time_received_ns/1000000000, 9) AS time_received,
            toDateTime64(time_flow_start_ns/1000000000, 9) AS time_flow_start,
            toDateTime64(time_flow_end_ns/1000000000, 9) AS time_flow_end,

            bytes * default_sampling_rate AS bytes,
            packets * default_sampling_rate AS packets,

            convertFixedStringIpToString(src_addr) AS src_addr_string,
            convertFixedStringIpToString(dst_addr) AS dst_addr_string,

            etype,
            proto,

            tcp_flags,

            src_port,
            dst_port,

            src_as,
            dst_as,

            convertFixedStringIpToString(next_hop) AS next_hop,
            next_hop_as,

            in_if,
            out_if,

            MACNumToString(src_mac) AS src_mac,
            MACNumToString(dst_mac) AS dst_mac,

            forwarding_status,

            observation_domain_id,
            observation_point_id
        FROM flows
    )
    SELECT
        type,

        sequence_num,
        sampler_address_string AS sampler_address,

        time_received,
        time_flow_start,
        time_flow_end,

        bytes,
        packets,

        src_addr_string AS src_addr,
        dst_addr_string AS dst_addr,

        etype,
        proto,

        tcp_flags,

        src_port,
        dst_port,

        src_as,
        dst_as,

        next_hop,
        next_hop_as,

        in_if,
        out_if,

        src_mac,
        dst_mac,

        forwarding_status,

        observation_domain_id,
        observation_point_id
    FROM temp;

CREATE TABLE IF NOT EXISTS prefix_flows_1m
(
    time_flow_start DateTime,

    prefix LowCardinality(String),

    total_flows UInt64,
    total_bytes UInt64,
    total_packets UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_flow_start)
ORDER BY (prefix, time_flow_start)
TTL toDate(time_flow_start) + INTERVAL 30 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS prefix_flows_1m_mv TO prefix_flows_1m AS
    SELECT
        toStartOfMinute(time_flow_start) AS time_flow_start,

        dictGetStringOrDefault('dictionaries.prefixes', 'prefix', toIPv6(dst_addr), '') AS prefix,

        count() AS total_flows,
        sum(bytes) AS total_bytes,
        sum(packets) AS total_packets
    FROM flows_raw
    WHERE prefix <> ''
    GROUP BY prefix, time_flow_start;

CREATE FUNCTION IF NOT EXISTS fireStaticBpsThresholdAlert AS (ip_prefix, threshold, duration, `datetime`) ->
(
    WITH result AS (
        SELECT
            total_bytes * 8 / 60 AS bps,
            bps >= threshold AS is_exceeded
        FROM prefix_flows_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_flow_start >= `datetime` - duration AND
            time_flow_start <= `datetime`
    )
    SELECT countIf(is_exceeded = true) = date_diff('minute', `datetime` - duration, `datetime`) FROM result
);

-- Usage example (check if the 10.0.0.0/24 prefix has exceeded the 100 Mbps threshold for the entire last hour):
-- SELECT fireStaticBpsThresholdAlert('10.0.0.0/24', 100000000, INTERVAL 1 HOUR, now());

CREATE FUNCTION IF NOT EXISTS fireStaticPpsThresholdAlert AS (ip_prefix, threshold, duration, `datetime`) ->
(
    WITH result AS (
        SELECT
            total_packets / 60 AS pps,
            pps >= threshold AS is_exceeded
        FROM prefix_flows_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_flow_start >= `datetime` - duration AND
            time_flow_start <= `datetime`
    )
    SELECT countIf(is_exceeded = true) = date_diff('minute', `datetime` - duration, `datetime`) FROM result
);

-- the formula for calculating the dynamic threshold is based on:
-- https://developers.cloudflare.com/magic-network-monitoring/rules/dynamic-threshold/#how-the-dynamic-rule-threshold-is-calculated

-- sensitivity levels:
-- high: z-score >= 4
-- medium: z-score >= 3
-- low: z-score >= 2

-- Usage example:
-- SELECT fireDynamicBpsThresholdAlert('10.0.0.0/24', 'medium', now());

CREATE FUNCTION IF NOT EXISTS fireDynamicBpsThresholdAlert AS (ip_prefix, sensitivity, `datetime`) ->
(
    WITH short_window AS (
        SELECT
            avg(total_bytes * 8 / 60) AS avg_bps
        FROM prefix_flows_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_flow_start >= `datetime` - INTERVAL 5 MINUTE AND
            time_flow_start <= `datetime`
    ),
    long_window AS (
        SELECT
            stddevPopStable(total_bytes * 8 / 60) AS stddev_bps,
            avg(total_bytes * 8 / 60) AS avg_bps
        FROM prefix_flows_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_flow_start >= `datetime` - INTERVAL 4 HOUR AND
            time_flow_start <= `datetime`
    ),
    result AS (
        SELECT
            (short_window.avg_bps - long_window.avg_bps) / long_window.stddev_bps AS z_score
        FROM short_window, long_window
    )
    SELECT
        (
            (sensitivity = 'high' AND result.z_score >= 4) OR
            (sensitivity = 'medium' AND result.z_score >= 3) OR
            (sensitivity = 'low' AND result.z_score >= 2)
        )
    FROM result
);

CREATE FUNCTION IF NOT EXISTS fireDynamicPpsThresholdAlert AS (ip_prefix, sensitivity, `datetime`) ->
(
    WITH short_window AS (
        SELECT
            avg(total_packets / 60) AS avg_pps
        FROM prefix_flows_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_flow_start >= `datetime` - INTERVAL 5 MINUTE AND
            time_flow_start <= `datetime`
    ),
    long_window AS (
        SELECT
            stddevPopStable(total_packets / 60) AS stddev_pps,
            avg(total_packets / 60) AS avg_pps
        FROM prefix_flows_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_flow_start >= `datetime` - INTERVAL 4 HOUR AND
            time_flow_start <= `datetime`
    ),
    result AS (
        SELECT
            (short_window.avg_pps - long_window.avg_pps) / long_window.stddev_pps AS z_score
        FROM short_window, long_window
    )
    SELECT
        (
            (sensitivity = 'high' AND result.z_score >= 4) OR
            (sensitivity = 'medium' AND result.z_score >= 3) OR
            (sensitivity = 'low' AND result.z_score >= 2)
        )
    FROM result
);
