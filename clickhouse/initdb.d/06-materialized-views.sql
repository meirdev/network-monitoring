CREATE MATERIALIZED VIEW IF NOT EXISTS flows.raw_mv TO flows.raw AS
    WITH temp AS (
        SELECT
            type,
            NumToFlowTypeString(type) AS type_str, 

            sequence_num,
            sampling_rate,

            BytesToIPString(fks.sampler_address) AS sampler_address_str,
            BytesToIPNum(fks.sampler_address) AS sampler_address,

            toDateTime64(time_received_ns/1000000000, 9) AS time_received,
            toDateTime64(time_flow_start_ns/1000000000, 9) AS time_flow_start,
            toDateTime64(time_flow_end_ns/1000000000, 9) AS time_flow_end,

            bytes,
            bytes * if(sampling_rate = 0, flows.routers.default_sampling, sampling_rate) AS total_bytes,

            packets,
            packets * if(sampling_rate = 0, flows.routers.default_sampling, sampling_rate) AS total_packets,

            BytesToIPString(fks.src_addr) AS src_addr_str,
            BytesToIPNum(fks.src_addr) AS src_addr,

            BytesToIPString(fks.dst_addr) AS dst_addr_str,
            BytesToIPNum(fks.dst_addr) AS dst_addr,

            etype,
            NumToETypeString(etype) AS etype_str,

            proto,
            NumToProtoString(proto) AS proto_str,

            ip_tos,
            ip_ttl,
            ip_flags,

            tcp_flags,
            NumToTcpFlagsString(tcp_flags) AS tcp_flags_str,

            icmp_type,
            icmp_code,

            src_port,
            dst_port,

            src_as,
            dst_as,

            src_net,
            dst_net,

            BytesToIPNum(next_hop) AS next_hop,

            next_hop_as,

            BytesToIPNum(bgp_next_hop) AS bgp_next_hop,

            in_if,
            out_if,

            src_mac,
            dst_mac,

            forwarding_status,
            -- Fix for Juniper devices with `report-zero-oif-gw-on-discard` enabled:
            NumToForwardingStatusString(if(empty(fks.next_hop) = 1 AND out_if = 0, 2, forwarding_status)) AS forwarding_status_str,

            observation_domain_id,
            observation_point_id
        FROM flows.kafka_sink fks
        LEFT ANY JOIN flows.routers ON sampler_address_str == flows.routers.router_ip
    ),
    ip_list AS (
        SELECT DISTINCT dst_addr FROM temp
    ),
    dst_addr_to_prefixes AS (
        SELECT
            dst_addr,
            groupArray(p.prefix) AS prefixes
        FROM ip_list l, flows.prefixes_range p
        WHERE dst_addr BETWEEN p.start AND p.end
        GROUP BY dst_addr
    )
    SELECT
        temp.*,
        prefixes
    FROM temp
    LEFT JOIN dst_addr_to_prefixes USING dst_addr;


-- CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_total_1m_mv TO flows.prefixes_total_1m AS
--     SELECT
--         dictGetStringOrDefault('flows.prefixes', 'prefix', toIPv6(dst_addr_str), '') AS prefix,

--         toStartOfMinute(time_received) AS time_received,

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
    SELECT
        arrayJoin(prefixes) AS prefix,

        toStartOfMinute(time_received) AS time_received,

        sum(total_bytes) AS bytes,
        sum(total_packets) AS packets,
        count() AS flows
    FROM flows.raw
    GROUP BY prefix, time_received;


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_src_profile_10m_mv TO flows.prefixes_src_profile_10m AS
    SELECT
        arrayJoin(prefixes) AS prefix,

        multiIf(
            etype = 0x800,
            IPv4NumToString(IPv4CIDRToRange(toIPv4(src_addr_str), 24).1),
            etype = 0x86dd,
            IPv6NumToString(IPv6CIDRToRange(toIPv6(src_addr_str), 64).1),
            null
        ) AS network,

        toStartOfTenMinutes(time_received) AS time_received,

        sum(total_bytes) AS bytes,
        sum(total_packets) AS packets,
        count() AS flows
    FROM flows.raw
    WHERE network IS NOT NULL
    GROUP BY prefix, network, time_received;


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_proto_profile_1m_mv TO flows.prefixes_proto_profile_1m AS
    WITH classified_flows AS (
        SELECT
            prefix,
            toStartOfMinute(time_received) AS time_received,
            proto,
            sum(total_bytes) AS bytes,
            sum(total_packets) AS packets,
            count() AS flows
        FROM flows.raw
        ARRAY JOIN prefixes AS prefix
        LEFT ARRAY JOIN
            arrayMap(x -> x.2, arrayFilter(x -> x.1, [
                (true, 'general'),
                (proto = 0, 'hopopt'),
                (proto = 6, 'tcp'),
                (proto = 17, 'udp'),
                (proto = 47, 'gre'),
                (proto = 50, 'esp'),
                ((etype = 0x0800 AND proto = 1) OR (etype = 0x86dd AND proto = 58), 'icmp'),
                (proto = 6 AND bitAnd(tcp_flags, 0x02) = 0x02, 'tcp_syn'),
                (proto = 6 AND bitAnd(tcp_flags, 0x04) = 0x04, 'tcp_rst'),
                (proto = 6 AND bitAnd(tcp_flags, 0x10) = 0x10, 'tcp_ack')
            ])) AS proto
        GROUP BY prefix, time_received, proto
    )
    SELECT
        prefix,
        time_received,

        [proto] AS `protoMap.proto`,
        [sum(bytes)] AS `protoMap.bytes`,
        [sum(packets)] AS `protoMap.packets`,
        [sum(flows)] AS `protoMap.flows`
    FROM classified_flows
    GROUP BY prefix, time_received, proto;
