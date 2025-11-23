CREATE MATERIALIZED VIEW IF NOT EXISTS flows.raw_mv TO flows.raw AS
    SELECT
        type,

        sequence_num,
        sampling_rate,
        sampler_address,

        time_received_ns,
        time_flow_start_ns,
        time_flow_end_ns,

        bytes,
        packets,

        src_addr,
        dst_addr,

        etype,
        proto,

        tcp_flags,

        icmp_type,
        icmp_code,

        src_port,
        dst_port,

        src_as,
        dst_as,

        src_net,
        dst_net,

        next_hop,
        next_hop_as,

        bgp_next_hop,

        in_if,
        out_if,

        src_mac,
        dst_mac,

        forwarding_status,

        observation_domain_id,
        observation_point_id,

        BytesToIPString(sampler_address) AS sampler_address_str,

        toDateTime64(time_received_ns/1000000000, 9) AS time_received_dt,
        toDateTime64(time_flow_start_ns/1000000000, 9) AS time_flow_start_dt,
        toDateTime64(time_flow_end_ns/1000000000, 9) AS time_flow_end_dt,

        bytes * if(sampling_rate = 0, flows.routers.default_sampling, sampling_rate) AS total_bytes,
        packets * if(sampling_rate = 0, flows.routers.default_sampling, sampling_rate) AS total_packets,

        BytesToIPString(src_addr) AS src_addr_str,
        BytesToIPString(dst_addr) AS dst_addr_str,

        NumToETypeString(etype) AS etype_str,
        NumToProtoString(proto) AS proto_str,

        NumToTcpFlagsString(tcp_flags) AS tcp_flags_str,

        -- Fix for Juniper devices with `report-zero-oif-gw-on-discard` enabled:
        NumToForwardingStatusString(if(empty(next_hop) = 1 AND out_if = 0, 2, forwarding_status)) AS forwarding_status_str
    FROM flows.kafka_sink
    LEFT ANY JOIN flows.routers ON sampler_address_str == flows.routers.router_ip;


-- CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_total_1m_mv TO flows.prefixes_total_1m AS
--     SELECT
--         dictGetStringOrDefault('flows.prefixes', 'prefix', toIPv6(dst_addr_str), '') AS prefix,

--         toStartOfMinute(time_received_dt) AS time_received,

--         sum(total_bytes) AS bytes,
--         sum(total_packets) AS packets,
--         count() AS flows
--     FROM flows.raw
--     WHERE prefix <> ''
--     GROUP BY prefix, time_received;


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_range_mv
REFRESH EVERY 1 MINUTE TO flows.prefixes_range AS
    WITH split_prefix AS (
        SELECT
            arrayJoin(prefixes) AS prefix,
            splitByChar('/', prefix) AS ip_mask,
            ip_mask[1] AS ip,
            toUInt8(ip_mask[2]) AS mask
        FROM flows.rules
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


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_total_1m_mv TO flows.prefixes_total_1m AS
    WITH ip_list AS (
        SELECT DISTINCT IPStringToNum(dst_addr_str) AS ip_num, dst_addr AS ip_bin FROM flows.raw
    ),
    prefixes AS (
        SELECT
            p.prefix,
            l.ip_bin
        FROM ip_list l, flows.prefixes_range p
        WHERE l.ip_num BETWEEN p.start AND p.end
    )
    SELECT
        prefixes.prefix AS prefix,

        toStartOfMinute(time_received_dt) AS time_received,

        sum(total_bytes) AS bytes,
        sum(total_packets) AS packets,
        count() AS flows
    FROM flows.raw
    LEFT JOIN prefixes ON flows.raw.dst_addr = prefixes.ip_bin
    WHERE prefix <> ''
    GROUP BY prefix, time_received;
