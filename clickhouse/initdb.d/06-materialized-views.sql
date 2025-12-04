CREATE MATERIALIZED VIEW IF NOT EXISTS flows.raw_mv TO flows.raw AS
    WITH temp AS (
        SELECT
            type,
            NumToFlowTypeString(type) AS type_str, 

            sequence_num,
            sampling_rate,

            BytesToIPString(fks.sampler_address) AS sampler_address_str,
            IPStringToNum(sampler_address_str) AS sampler_address,

            toDateTime64(time_received_ns/1000000000, 9) AS time_received,
            toDateTime64(time_flow_start_ns/1000000000, 9) AS time_flow_start,
            toDateTime64(time_flow_end_ns/1000000000, 9) AS time_flow_end,

            bytes,
            bytes * if(sampling_rate = 0, flows.routers.default_sampling, sampling_rate) AS total_bytes,

            packets,
            packets * if(sampling_rate = 0, flows.routers.default_sampling, sampling_rate) AS total_packets,

            BytesToIPString(fks.src_addr) AS src_addr_str,
            IPStringToNum(src_addr_str) AS src_addr,

            BytesToIPString(fks.dst_addr) AS dst_addr_str,
            IPStringToNum(dst_addr_str) AS dst_addr,

            etype,
            NumToETypeString(etype) AS etype_str,

            proto,
            NumToProtoString(proto) AS proto_str,

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

            IPStringToNum(BytesToIPString(next_hop)) AS next_hop,

            next_hop_as,

            IPStringToNum(BytesToIPString(bgp_next_hop)) AS bgp_next_hop,

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


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_dst_profile_10m_mv TO flows.prefixes_dst_profile_10m AS
    SELECT
        prefix,
        time_received,

        [proto_str] AS `protoMap.proto`,
        [bytes] AS `protoMap.bytes`,
        [packets] AS `protoMap.packets`,
        [flows] AS `protoMap.flows`,

        [tcp_flag] AS `tcpFlagMap.tcp_flag`,
        [bytes] AS `tcpFlagMap.bytes`,
        [packets] AS `tcpFlagMap.packets`,
        [flows] AS `tcpFlagMap.flows`,

        sum(bytes) AS bytes,
        sum(packets) AS packets,
        sum(flows) AS flows
    FROM (
        SELECT
            prefix,
            toStartOfTenMinutes(time_received) AS time_received,
            proto_str,
            NumToTcpFlagString(tcp_flag) AS tcp_flag,
            sum(total_bytes) AS bytes,
            sum(total_packets) AS packets,
            count() AS flows
        FROM flows.raw
        ARRAY JOIN prefixes AS prefix
        LEFT ARRAY JOIN
            arrayFilter(x -> x != 0, [
                bitAnd(tcp_flags, 1),   -- FIN
                bitAnd(tcp_flags, 2),   -- SYN
                bitAnd(tcp_flags, 4),   -- RST
                bitAnd(tcp_flags, 8),   -- PSH
                bitAnd(tcp_flags, 16),  -- ACK
                bitAnd(tcp_flags, 32),  -- URG
                bitAnd(tcp_flags, 64),  -- ECE
                bitAnd(tcp_flags, 128)  -- CWR
            ]) AS tcp_flag
        GROUP BY prefix, time_received, proto_str, tcp_flag
    )
    GROUP BY prefix, time_received, proto_str, tcp_flag;
