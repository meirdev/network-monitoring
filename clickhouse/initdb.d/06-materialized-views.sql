CREATE MATERIALIZED VIEW IF NOT EXISTS flows.raw_mv TO flows.raw
AS WITH
    temp AS
    (
        SELECT
            type,
            NumToFlowTypeString(type) AS type_str,
            sequence_num,
            sampling_rate,
            BytesToIPString(fks.sampler_address) AS sampler_address_str,
            BytesToIPNum(fks.sampler_address) AS sampler_address,
            toDateTime64(time_received_ns / 1000000000, 9) AS time_received,
            toDateTime64(time_flow_start_ns / 1000000000, 9) AS time_flow_start,
            toDateTime64(time_flow_end_ns / 1000000000, 9) AS time_flow_end,
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
            NumToForwardingStatusString(if((empty(fks.next_hop) = 1) AND (out_if = 0), 2, forwarding_status)) AS forwarding_status_str,
            observation_domain_id,
            observation_point_id
        FROM flows.kafka_sink AS fks
        ANY LEFT JOIN flows.routers ON sampler_address_str = flows.routers.router_ip
    ),
    ip_list AS
    (
        SELECT DISTINCT dst_addr
        FROM temp
    ),
    dst_addr_to_prefixes AS
    (
        SELECT
            dst_addr,
            groupArray(p.prefix) AS prefixes
        FROM ip_list AS l, flows.prefixes_range AS p
        WHERE (dst_addr >= p.start) AND (dst_addr <= p.end)
        GROUP BY dst_addr
    )
SELECT
    temp.*,
    prefixes
FROM temp
LEFT JOIN dst_addr_to_prefixes USING (dst_addr);

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_range_mv
REFRESH EVERY 1 MINUTE TO flows.prefixes_range
AS WITH
    split_prefix AS
    (
        SELECT DISTINCT
            arrayJoin(prefixes) AS prefix,
            splitByChar('/', prefix) AS ip_mask,
            ip_mask[1] AS ip,
            toUInt8(ip_mask[2]) AS mask
        FROM flows.rules
    ),
    ipv4_prefixes AS
    (
        SELECT
            prefix,
            IPv4CIDRToRange(IPv4StringToNum(ip), mask) AS ip_range
        FROM split_prefix
        WHERE position(ip, '.') != 0
    ),
    ipv6_prefixes AS
    (
        SELECT
            prefix,
            IPv6CIDRToRange(IPv6StringToNum(ip), mask) AS ip_range
        FROM split_prefix
        WHERE position(ip, '.') = 0
    )
SELECT
    prefix,
    toUInt128(ip_range.1) AS start,
    toUInt128(ip_range.2) AS end
FROM ipv4_prefixes
UNION ALL
SELECT
    prefix,
    toUInt128(ip_range.1) AS start,
    toUInt128(ip_range.2) AS end
FROM ipv6_prefixes
ORDER BY
    start ASC,
    end ASC;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_src_1h_mv TO flows.prefixes_src_1h
AS SELECT
    arrayJoin(prefixes) AS prefix,
    multiIf(etype = 2048, IPv4NumToString((IPv4CIDRToRange(toIPv4(src_addr_str), 16)).1), etype = 34525, IPv6NumToString((IPv6CIDRToRange(toIPv6(src_addr_str), 32)).1), NULL) AS network,
    toStartOfHour(time_received) AS time_received,
    sum(total_bytes) AS bytes,
    sum(total_packets) AS packets,
    count() AS flows
FROM flows.raw
WHERE network IS NOT NULL
GROUP BY
    prefix,
    network,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_src_1d_mv
REFRESH EVERY 1 DAY APPEND TO flows.prefixes_src_1d
AS SELECT
    prefix,
    network,
    toStartOfDay(time_received) AS time_received,
    sum(bytes) AS bytes,
    sum(packets) AS packets,
    sum(flows) AS flows
FROM flows.prefixes_src_1h
WHERE time_received >= (NOW() - toIntervalDay(1))
GROUP BY
    prefix,
    network,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_ip_port_1m_mv TO flows.prefixes_ip_port_1m
AS WITH precomputed AS
    (
        SELECT
            arrayJoin(prefixes) AS prefix,
            dst_addr_str AS dst_addr,
            dst_port,
            toStartOfMinute(time_received) AS time_received,
            total_bytes,
            total_packets,
            proto = 6 AS is_tcp,
            proto = 17 AS is_udp,
            proto = 47 AS is_gre,
            proto = 50 AS is_esp,
            ((etype = 2048) AND (proto = 1)) OR ((etype = 34525) AND (proto = 58)) AS is_icmp,
            is_tcp AND bitAnd(tcp_flags, 1) AS is_tcp_fin,
            is_tcp AND bitAnd(tcp_flags, 2) AS is_tcp_syn,
            is_tcp AND bitAnd(tcp_flags, 4) AS is_tcp_rst,
            is_tcp AND bitAnd(tcp_flags, 8) AS is_tcp_psh,
            is_tcp AND bitAnd(tcp_flags, 16) AS is_tcp_ack,
            is_tcp AND bitAnd(tcp_flags, 32) AS is_tcp_urg
        FROM flows.raw
    )
SELECT
    prefix,
    dst_addr,
    dst_port,
    time_received,
    sum(total_bytes) AS any_bytes,
    sum(total_packets) AS any_packets,
    count() AS any_flows,
    sumIf(total_bytes, is_tcp) AS tcp_bytes,
    sumIf(total_packets, is_tcp) AS tcp_packets,
    countIf(is_tcp) AS tcp_flows,
    sumIf(total_bytes, is_udp) AS udp_bytes,
    sumIf(total_packets, is_udp) AS udp_packets,
    countIf(is_udp) AS udp_flows,
    sumIf(total_bytes, is_gre) AS gre_bytes,
    sumIf(total_packets, is_gre) AS gre_packets,
    countIf(is_gre) AS gre_flows,
    sumIf(total_bytes, is_esp) AS esp_bytes,
    sumIf(total_packets, is_esp) AS esp_packets,
    countIf(is_esp) AS esp_flows,
    sumIf(total_bytes, is_icmp) AS icmp_bytes,
    sumIf(total_packets, is_icmp) AS icmp_packets,
    countIf(is_icmp) AS icmp_flows,
    sumIf(total_bytes, is_tcp_fin) AS tcp_fin_bytes,
    sumIf(total_packets, is_tcp_fin) AS tcp_fin_packets,
    countIf(is_tcp_fin) AS tcp_fin_flows,
    sumIf(total_bytes, is_tcp_syn) AS tcp_syn_bytes,
    sumIf(total_packets, is_tcp_syn) AS tcp_syn_packets,
    countIf(is_tcp_syn) AS tcp_syn_flows,
    sumIf(total_bytes, is_tcp_rst) AS tcp_rst_bytes,
    sumIf(total_packets, is_tcp_rst) AS tcp_rst_packets,
    countIf(is_tcp_rst) AS tcp_rst_flows,
    sumIf(total_bytes, is_tcp_psh) AS tcp_psh_bytes,
    sumIf(total_packets, is_tcp_psh) AS tcp_psh_packets,
    countIf(is_tcp_psh) AS tcp_psh_flows,
    sumIf(total_bytes, is_tcp_ack) AS tcp_ack_bytes,
    sumIf(total_packets, is_tcp_ack) AS tcp_ack_packets,
    countIf(is_tcp_ack) AS tcp_ack_flows,
    sumIf(total_bytes, is_tcp_urg) AS tcp_urg_bytes,
    sumIf(total_packets, is_tcp_urg) AS tcp_urg_packets,
    countIf(is_tcp_urg) AS tcp_urg_flows
FROM precomputed
GROUP BY
    prefix,
    dst_addr,
    dst_port,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_ip_1m_mv TO flows.prefixes_ip_1m
AS SELECT
    prefix,
    dst_addr,
    time_received,
    sum(any_bytes) AS any_bytes,
    sum(any_packets) AS any_packets,
    sum(any_flows) AS any_flows,
    sum(tcp_bytes) AS tcp_bytes,
    sum(tcp_packets) AS tcp_packets,
    sum(tcp_flows) AS tcp_flows,
    sum(udp_bytes) AS udp_bytes,
    sum(udp_packets) AS udp_packets,
    sum(udp_flows) AS udp_flows,
    sum(gre_bytes) AS gre_bytes,
    sum(gre_packets) AS gre_packets,
    sum(gre_flows) AS gre_flows,
    sum(esp_bytes) AS esp_bytes,
    sum(esp_packets) AS esp_packets,
    sum(esp_flows) AS esp_flows,
    sum(icmp_bytes) AS icmp_bytes,
    sum(icmp_packets) AS icmp_packets,
    sum(icmp_flows) AS icmp_flows,
    sum(tcp_fin_bytes) AS tcp_fin_bytes,
    sum(tcp_fin_packets) AS tcp_fin_packets,
    sum(tcp_fin_flows) AS tcp_fin_flows,
    sum(tcp_syn_bytes) AS tcp_syn_bytes,
    sum(tcp_syn_packets) AS tcp_syn_packets,
    sum(tcp_syn_flows) AS tcp_syn_flows,
    sum(tcp_rst_bytes) AS tcp_rst_bytes,
    sum(tcp_rst_packets) AS tcp_rst_packets,
    sum(tcp_rst_flows) AS tcp_rst_flows,
    sum(tcp_psh_bytes) AS tcp_psh_bytes,
    sum(tcp_psh_packets) AS tcp_psh_packets,
    sum(tcp_psh_flows) AS tcp_psh_flows,
    sum(tcp_ack_bytes) AS tcp_ack_bytes,
    sum(tcp_ack_packets) AS tcp_ack_packets,
    sum(tcp_ack_flows) AS tcp_ack_flows,
    sum(tcp_urg_bytes) AS tcp_urg_bytes,
    sum(tcp_urg_packets) AS tcp_urg_packets,
    sum(tcp_urg_flows) AS tcp_urg_flows
FROM flows.prefixes_ip_port_1m
GROUP BY
    prefix,
    dst_addr,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_proto_1m_mv TO flows.prefixes_proto_1m
AS SELECT
    prefix,
    time_received,
    sum(any_bytes) AS any_bytes,
    sum(any_packets) AS any_packets,
    sum(any_flows) AS any_flows,
    sum(tcp_bytes) AS tcp_bytes,
    sum(tcp_packets) AS tcp_packets,
    sum(tcp_flows) AS tcp_flows,
    sum(udp_bytes) AS udp_bytes,
    sum(udp_packets) AS udp_packets,
    sum(udp_flows) AS udp_flows,
    sum(gre_bytes) AS gre_bytes,
    sum(gre_packets) AS gre_packets,
    sum(gre_flows) AS gre_flows,
    sum(esp_bytes) AS esp_bytes,
    sum(esp_packets) AS esp_packets,
    sum(esp_flows) AS esp_flows,
    sum(icmp_bytes) AS icmp_bytes,
    sum(icmp_packets) AS icmp_packets,
    sum(icmp_flows) AS icmp_flows,
    sum(tcp_fin_bytes) AS tcp_fin_bytes,
    sum(tcp_fin_packets) AS tcp_fin_packets,
    sum(tcp_fin_flows) AS tcp_fin_flows,
    sum(tcp_syn_bytes) AS tcp_syn_bytes,
    sum(tcp_syn_packets) AS tcp_syn_packets,
    sum(tcp_syn_flows) AS tcp_syn_flows,
    sum(tcp_rst_bytes) AS tcp_rst_bytes,
    sum(tcp_rst_packets) AS tcp_rst_packets,
    sum(tcp_rst_flows) AS tcp_rst_flows,
    sum(tcp_psh_bytes) AS tcp_psh_bytes,
    sum(tcp_psh_packets) AS tcp_psh_packets,
    sum(tcp_psh_flows) AS tcp_psh_flows,
    sum(tcp_ack_bytes) AS tcp_ack_bytes,
    sum(tcp_ack_packets) AS tcp_ack_packets,
    sum(tcp_ack_flows) AS tcp_ack_flows,
    sum(tcp_urg_bytes) AS tcp_urg_bytes,
    sum(tcp_urg_packets) AS tcp_urg_packets,
    sum(tcp_urg_flows) AS tcp_urg_flows
FROM flows.prefixes_ip_1m
GROUP BY
    prefix,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_ip_port_1h_mv
REFRESH EVERY 1 HOUR APPEND TO flows.prefixes_ip_port_1h
AS WITH
    per_minute AS
    (
        SELECT
            *,
            (any_bytes * 8) / 60 AS any_bps,
            any_packets / 60 AS any_pps,
            (tcp_bytes * 8) / 60 AS tcp_bps,
            tcp_packets / 60 AS tcp_pps,
            (udp_bytes * 8) / 60 AS udp_bps,
            udp_packets / 60 AS udp_pps,
            (gre_bytes * 8) / 60 AS gre_bps,
            gre_packets / 60 AS gre_pps,
            (esp_bytes * 8) / 60 AS esp_bps,
            esp_packets / 60 AS esp_pps,
            (icmp_bytes * 8) / 60 AS icmp_bps,
            icmp_packets / 60 AS icmp_pps
        FROM flows.prefixes_ip_port_1m
        FINAL
        WHERE time_received >= (NOW() - toIntervalHour(1))
    ),
    stats AS
    (
        SELECT
            prefix,
            dst_addr,
            dst_port,
            toStartOfHour(time_received) AS time_received,
            sum(any_bytes) AS any_bytes,
            sum(any_packets) AS any_packets,
            sum(any_flows) AS any_flows,
            sum(tcp_bytes) AS tcp_bytes,
            sum(tcp_packets) AS tcp_packets,
            sum(tcp_flows) AS tcp_flows,
            sum(udp_bytes) AS udp_bytes,
            sum(udp_packets) AS udp_packets,
            sum(udp_flows) AS udp_flows,
            sum(gre_bytes) AS gre_bytes,
            sum(gre_packets) AS gre_packets,
            sum(gre_flows) AS gre_flows,
            sum(esp_bytes) AS esp_bytes,
            sum(esp_packets) AS esp_packets,
            sum(esp_flows) AS esp_flows,
            sum(icmp_bytes) AS icmp_bytes,
            sum(icmp_packets) AS icmp_packets,
            sum(icmp_flows) AS icmp_flows,
            min(any_bps) AS any_min_bps,
            max(any_bps) AS any_max_bps,
            quantile(0.95)(any_bps) AS any_p95_bps,
            min(any_pps) AS any_min_pps,
            max(any_pps) AS any_max_pps,
            quantile(0.95)(any_pps) AS any_p95_pps,
            min(tcp_bps) AS tcp_min_bps,
            max(tcp_bps) AS tcp_max_bps,
            quantile(0.95)(tcp_bps) AS tcp_p95_bps,
            min(tcp_pps) AS tcp_min_pps,
            max(tcp_pps) AS tcp_max_pps,
            quantile(0.95)(tcp_pps) AS tcp_p95_pps,
            min(udp_bps) AS udp_min_bps,
            max(udp_bps) AS udp_max_bps,
            quantile(0.95)(udp_bps) AS udp_p95_bps,
            min(udp_pps) AS udp_min_pps,
            max(udp_pps) AS udp_max_pps,
            quantile(0.95)(udp_pps) AS udp_p95_pps,
            min(gre_bps) AS gre_min_bps,
            max(gre_bps) AS gre_max_bps,
            quantile(0.95)(gre_bps) AS gre_p95_bps,
            min(gre_pps) AS gre_min_pps,
            max(gre_pps) AS gre_max_pps,
            quantile(0.95)(gre_pps) AS gre_p95_pps,
            min(esp_bps) AS esp_min_bps,
            max(esp_bps) AS esp_max_bps,
            quantile(0.95)(esp_bps) AS esp_p95_bps,
            min(esp_pps) AS esp_min_pps,
            max(esp_pps) AS esp_max_pps,
            quantile(0.95)(esp_pps) AS esp_p95_pps,
            min(icmp_bps) AS icmp_min_bps,
            max(icmp_bps) AS icmp_max_bps,
            quantile(0.95)(icmp_bps) AS icmp_p95_bps,
            min(icmp_pps) AS icmp_min_pps,
            max(icmp_pps) AS icmp_max_pps,
            quantile(0.95)(icmp_pps) AS icmp_p95_pps
        FROM per_minute
        GROUP BY
            prefix,
            dst_addr,
            dst_port,
            time_received
    )
SELECT *
FROM stats
QUALIFY any_bytes >= quantile(0.05)(any_bytes) OVER (PARTITION BY prefix, dst_addr);

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_ip_1h_mv
REFRESH EVERY 1 HOUR APPEND TO flows.prefixes_ip_1h
AS WITH per_minute AS
    (
        SELECT
            *,
            (any_bytes * 8) / 60 AS any_bps,
            any_packets / 60 AS any_pps,
            (tcp_bytes * 8) / 60 AS tcp_bps,
            tcp_packets / 60 AS tcp_pps,
            (udp_bytes * 8) / 60 AS udp_bps,
            udp_packets / 60 AS udp_pps,
            (gre_bytes * 8) / 60 AS gre_bps,
            gre_packets / 60 AS gre_pps,
            (esp_bytes * 8) / 60 AS esp_bps,
            esp_packets / 60 AS esp_pps,
            (icmp_bytes * 8) / 60 AS icmp_bps,
            icmp_packets / 60 AS icmp_pps
        FROM flows.prefixes_ip_1m
        FINAL
        WHERE time_received >= (NOW() - toIntervalHour(1))
    )
SELECT
    prefix,
    dst_addr,
    toStartOfHour(time_received) AS time_received,
    sum(any_bytes) AS any_bytes,
    sum(any_packets) AS any_packets,
    sum(any_flows) AS any_flows,
    sum(tcp_bytes) AS tcp_bytes,
    sum(tcp_packets) AS tcp_packets,
    sum(tcp_flows) AS tcp_flows,
    sum(udp_bytes) AS udp_bytes,
    sum(udp_packets) AS udp_packets,
    sum(udp_flows) AS udp_flows,
    sum(gre_bytes) AS gre_bytes,
    sum(gre_packets) AS gre_packets,
    sum(gre_flows) AS gre_flows,
    sum(esp_bytes) AS esp_bytes,
    sum(esp_packets) AS esp_packets,
    sum(esp_flows) AS esp_flows,
    sum(icmp_bytes) AS icmp_bytes,
    sum(icmp_packets) AS icmp_packets,
    sum(icmp_flows) AS icmp_flows,
    min(any_bps) AS any_min_bps,
    max(any_bps) AS any_max_bps,
    quantile(0.95)(any_bps) AS any_p95_bps,
    min(any_pps) AS any_min_pps,
    max(any_pps) AS any_max_pps,
    quantile(0.95)(any_pps) AS any_p95_pps,
    min(tcp_bps) AS tcp_min_bps,
    max(tcp_bps) AS tcp_max_bps,
    quantile(0.95)(tcp_bps) AS tcp_p95_bps,
    min(tcp_pps) AS tcp_min_pps,
    max(tcp_pps) AS tcp_max_pps,
    quantile(0.95)(tcp_pps) AS tcp_p95_pps,
    min(udp_bps) AS udp_min_bps,
    max(udp_bps) AS udp_max_bps,
    quantile(0.95)(udp_bps) AS udp_p95_bps,
    min(udp_pps) AS udp_min_pps,
    max(udp_pps) AS udp_max_pps,
    quantile(0.95)(udp_pps) AS udp_p95_pps,
    min(gre_bps) AS gre_min_bps,
    max(gre_bps) AS gre_max_bps,
    quantile(0.95)(gre_bps) AS gre_p95_bps,
    min(gre_pps) AS gre_min_pps,
    max(gre_pps) AS gre_max_pps,
    quantile(0.95)(gre_pps) AS gre_p95_pps,
    min(esp_bps) AS esp_min_bps,
    max(esp_bps) AS esp_max_bps,
    quantile(0.95)(esp_bps) AS esp_p95_bps,
    min(esp_pps) AS esp_min_pps,
    max(esp_pps) AS esp_max_pps,
    quantile(0.95)(esp_pps) AS esp_p95_pps,
    min(icmp_bps) AS icmp_min_bps,
    max(icmp_bps) AS icmp_max_bps,
    quantile(0.95)(icmp_bps) AS icmp_p95_bps,
    min(icmp_pps) AS icmp_min_pps,
    max(icmp_pps) AS icmp_max_pps,
    quantile(0.95)(icmp_pps) AS icmp_p95_pps
FROM per_minute
GROUP BY
    prefix,
    dst_addr,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_proto_1h_mv
REFRESH EVERY 1 HOUR APPEND TO flows.prefixes_proto_1h
AS WITH per_minute AS
    (
        SELECT
            *,
            (any_bytes * 8) / 60 AS any_bps,
            any_packets / 60 AS any_pps,
            (tcp_bytes * 8) / 60 AS tcp_bps,
            tcp_packets / 60 AS tcp_pps,
            (udp_bytes * 8) / 60 AS udp_bps,
            udp_packets / 60 AS udp_pps,
            (gre_bytes * 8) / 60 AS gre_bps,
            gre_packets / 60 AS gre_pps,
            (esp_bytes * 8) / 60 AS esp_bps,
            esp_packets / 60 AS esp_pps,
            (icmp_bytes * 8) / 60 AS icmp_bps,
            icmp_packets / 60 AS icmp_pps
        FROM flows.prefixes_proto_1m
        FINAL
        WHERE time_received >= (NOW() - toIntervalHour(1))
    )
SELECT
    prefix,
    toStartOfHour(time_received) AS time_received,
    sum(any_bytes) AS any_bytes,
    sum(any_packets) AS any_packets,
    sum(any_flows) AS any_flows,
    sum(tcp_bytes) AS tcp_bytes,
    sum(tcp_packets) AS tcp_packets,
    sum(tcp_flows) AS tcp_flows,
    sum(udp_bytes) AS udp_bytes,
    sum(udp_packets) AS udp_packets,
    sum(udp_flows) AS udp_flows,
    sum(gre_bytes) AS gre_bytes,
    sum(gre_packets) AS gre_packets,
    sum(gre_flows) AS gre_flows,
    sum(esp_bytes) AS esp_bytes,
    sum(esp_packets) AS esp_packets,
    sum(esp_flows) AS esp_flows,
    sum(icmp_bytes) AS icmp_bytes,
    sum(icmp_packets) AS icmp_packets,
    sum(icmp_flows) AS icmp_flows,
    min(any_bps) AS any_min_bps,
    max(any_bps) AS any_max_bps,
    quantile(0.95)(any_bps) AS any_p95_bps,
    min(any_pps) AS any_min_pps,
    max(any_pps) AS any_max_pps,
    quantile(0.95)(any_pps) AS any_p95_pps,
    min(tcp_bps) AS tcp_min_bps,
    max(tcp_bps) AS tcp_max_bps,
    quantile(0.95)(tcp_bps) AS tcp_p95_bps,
    min(tcp_pps) AS tcp_min_pps,
    max(tcp_pps) AS tcp_max_pps,
    quantile(0.95)(tcp_pps) AS tcp_p95_pps,
    min(udp_bps) AS udp_min_bps,
    max(udp_bps) AS udp_max_bps,
    quantile(0.95)(udp_bps) AS udp_p95_bps,
    min(udp_pps) AS udp_min_pps,
    max(udp_pps) AS udp_max_pps,
    quantile(0.95)(udp_pps) AS udp_p95_pps,
    min(gre_bps) AS gre_min_bps,
    max(gre_bps) AS gre_max_bps,
    quantile(0.95)(gre_bps) AS gre_p95_bps,
    min(gre_pps) AS gre_min_pps,
    max(gre_pps) AS gre_max_pps,
    quantile(0.95)(gre_pps) AS gre_p95_pps,
    min(esp_bps) AS esp_min_bps,
    max(esp_bps) AS esp_max_bps,
    quantile(0.95)(esp_bps) AS esp_p95_bps,
    min(esp_pps) AS esp_min_pps,
    max(esp_pps) AS esp_max_pps,
    quantile(0.95)(esp_pps) AS esp_p95_pps,
    min(icmp_bps) AS icmp_min_bps,
    max(icmp_bps) AS icmp_max_bps,
    quantile(0.95)(icmp_bps) AS icmp_p95_bps,
    min(icmp_pps) AS icmp_min_pps,
    max(icmp_pps) AS icmp_max_pps,
    quantile(0.95)(icmp_pps) AS icmp_p95_pps
FROM per_minute
GROUP BY
    prefix,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_ip_port_1d_mv
REFRESH EVERY 1 DAY APPEND TO flows.prefixes_ip_port_1d
AS WITH stats AS
    (
        SELECT
            prefix,
            dst_addr,
            dst_port,
            toStartOfDay(time_received) AS time_received,
            quantile(0.95)(any_bytes) AS any_p95_bytes,
            quantile(0.95)(any_packets) AS any_p95_packets,
            quantile(0.95)(any_flows) AS any_p95_flows,
            max(any_bytes) AS any_max_bytes,
            max(any_packets) AS any_max_packets,
            max(any_flows) AS any_max_flows,
            quantile(0.95)(tcp_bytes) AS tcp_p95_bytes,
            quantile(0.95)(tcp_packets) AS tcp_p95_packets,
            quantile(0.95)(tcp_flows) AS tcp_p95_flows,
            max(tcp_bytes) AS tcp_max_bytes,
            max(tcp_packets) AS tcp_max_packets,
            max(tcp_flows) AS tcp_max_flows,
            quantile(0.95)(udp_bytes) AS udp_p95_bytes,
            quantile(0.95)(udp_packets) AS udp_p95_packets,
            quantile(0.95)(udp_flows) AS udp_p95_flows,
            max(udp_bytes) AS udp_max_bytes,
            max(udp_packets) AS udp_max_packets,
            max(udp_flows) AS udp_max_flows,
            quantile(0.95)(gre_bytes) AS gre_p95_bytes,
            quantile(0.95)(gre_packets) AS gre_p95_packets,
            quantile(0.95)(gre_flows) AS gre_p95_flows,
            max(gre_bytes) AS gre_max_bytes,
            max(gre_packets) AS gre_max_packets,
            max(gre_flows) AS gre_max_flows,
            quantile(0.95)(esp_bytes) AS esp_p95_bytes,
            quantile(0.95)(esp_packets) AS esp_p95_packets,
            quantile(0.95)(esp_flows) AS esp_p95_flows,
            max(esp_bytes) AS esp_max_bytes,
            max(esp_packets) AS esp_max_packets,
            max(esp_flows) AS esp_max_flows,
            quantile(0.95)(icmp_bytes) AS icmp_p95_bytes,
            quantile(0.95)(icmp_packets) AS icmp_p95_packets,
            quantile(0.95)(icmp_flows) AS icmp_p95_flows,
            max(icmp_bytes) AS icmp_max_bytes,
            max(icmp_packets) AS icmp_max_packets,
            max(icmp_flows) AS icmp_max_flows,
            min(any_min_bps) AS any_min_bps,
            max(any_max_bps) AS any_max_bps,
            avg(any_p95_bps) AS any_p95_bps,
            min(any_min_pps) AS any_min_pps,
            max(any_max_pps) AS any_max_pps,
            avg(any_p95_pps) AS any_p95_pps,
            min(tcp_min_bps) AS tcp_min_bps,
            max(tcp_max_bps) AS tcp_max_bps,
            avg(tcp_p95_bps) AS tcp_p95_bps,
            min(tcp_min_pps) AS tcp_min_pps,
            max(tcp_max_pps) AS tcp_max_pps,
            avg(tcp_p95_pps) AS tcp_p95_pps,
            min(udp_min_bps) AS udp_min_bps,
            max(udp_max_bps) AS udp_max_bps,
            avg(udp_p95_bps) AS udp_p95_bps,
            min(udp_min_pps) AS udp_min_pps,
            max(udp_max_pps) AS udp_max_pps,
            avg(udp_p95_pps) AS udp_p95_pps,
            min(gre_min_bps) AS gre_min_bps,
            max(gre_max_bps) AS gre_max_bps,
            avg(gre_p95_bps) AS gre_p95_bps,
            min(gre_min_pps) AS gre_min_pps,
            max(gre_max_pps) AS gre_max_pps,
            avg(gre_p95_pps) AS gre_p95_pps,
            min(esp_min_bps) AS esp_min_bps,
            max(esp_max_bps) AS esp_max_bps,
            avg(esp_p95_bps) AS esp_p95_bps,
            min(esp_min_pps) AS esp_min_pps,
            max(esp_max_pps) AS esp_max_pps,
            avg(esp_p95_pps) AS esp_p95_pps,
            min(icmp_min_bps) AS icmp_min_bps,
            max(icmp_max_bps) AS icmp_max_bps,
            avg(icmp_p95_bps) AS icmp_p95_bps,
            min(icmp_min_pps) AS icmp_min_pps,
            max(icmp_max_pps) AS icmp_max_pps,
            avg(icmp_p95_pps) AS icmp_p95_pps,
            sum(any_bytes) AS total_bytes
        FROM flows.prefixes_ip_port_1h
        WHERE time_received >= (NOW() - toIntervalDay(1))
        GROUP BY
            prefix,
            dst_addr,
            dst_port,
            time_received
    )
SELECT * EXCEPT total_bytes
FROM stats
QUALIFY total_bytes >= quantile(0.05)(total_bytes) OVER (PARTITION BY prefix, dst_addr);

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_proto_1d_mv
REFRESH EVERY 1 DAY APPEND TO flows.prefixes_proto_1d
AS SELECT
    prefix,
    toStartOfDay(time_received) AS time_received,
    quantile(0.95)(any_bytes) AS any_p95_bytes,
    quantile(0.95)(any_packets) AS any_p95_packets,
    quantile(0.95)(any_flows) AS any_p95_flows,
    max(any_bytes) AS any_max_bytes,
    max(any_packets) AS any_max_packets,
    max(any_flows) AS any_max_flows,
    quantile(0.95)(tcp_bytes) AS tcp_p95_bytes,
    quantile(0.95)(tcp_packets) AS tcp_p95_packets,
    quantile(0.95)(tcp_flows) AS tcp_p95_flows,
    max(tcp_bytes) AS tcp_max_bytes,
    max(tcp_packets) AS tcp_max_packets,
    max(tcp_flows) AS tcp_max_flows,
    quantile(0.95)(udp_bytes) AS udp_p95_bytes,
    quantile(0.95)(udp_packets) AS udp_p95_packets,
    quantile(0.95)(udp_flows) AS udp_p95_flows,
    max(udp_bytes) AS udp_max_bytes,
    max(udp_packets) AS udp_max_packets,
    max(udp_flows) AS udp_max_flows,
    quantile(0.95)(gre_bytes) AS gre_p95_bytes,
    quantile(0.95)(gre_packets) AS gre_p95_packets,
    quantile(0.95)(gre_flows) AS gre_p95_flows,
    max(gre_bytes) AS gre_max_bytes,
    max(gre_packets) AS gre_max_packets,
    max(gre_flows) AS gre_max_flows,
    quantile(0.95)(esp_bytes) AS esp_p95_bytes,
    quantile(0.95)(esp_packets) AS esp_p95_packets,
    quantile(0.95)(esp_flows) AS esp_p95_flows,
    max(esp_bytes) AS esp_max_bytes,
    max(esp_packets) AS esp_max_packets,
    max(esp_flows) AS esp_max_flows,
    quantile(0.95)(icmp_bytes) AS icmp_p95_bytes,
    quantile(0.95)(icmp_packets) AS icmp_p95_packets,
    quantile(0.95)(icmp_flows) AS icmp_p95_flows,
    max(icmp_bytes) AS icmp_max_bytes,
    max(icmp_packets) AS icmp_max_packets,
    max(icmp_flows) AS icmp_max_flows,
    min(any_min_bps) AS any_min_bps,
    max(any_max_bps) AS any_max_bps,
    avg(any_p95_bps) AS any_p95_bps,
    min(any_min_pps) AS any_min_pps,
    max(any_max_pps) AS any_max_pps,
    avg(any_p95_pps) AS any_p95_pps,
    min(tcp_min_bps) AS tcp_min_bps,
    max(tcp_max_bps) AS tcp_max_bps,
    avg(tcp_p95_bps) AS tcp_p95_bps,
    min(tcp_min_pps) AS tcp_min_pps,
    max(tcp_max_pps) AS tcp_max_pps,
    avg(tcp_p95_pps) AS tcp_p95_pps,
    min(udp_min_bps) AS udp_min_bps,
    max(udp_max_bps) AS udp_max_bps,
    avg(udp_p95_bps) AS udp_p95_bps,
    min(udp_min_pps) AS udp_min_pps,
    max(udp_max_pps) AS udp_max_pps,
    avg(udp_p95_pps) AS udp_p95_pps,
    min(gre_min_bps) AS gre_min_bps,
    max(gre_max_bps) AS gre_max_bps,
    avg(gre_p95_bps) AS gre_p95_bps,
    min(gre_min_pps) AS gre_min_pps,
    max(gre_max_pps) AS gre_max_pps,
    avg(gre_p95_pps) AS gre_p95_pps,
    min(esp_min_bps) AS esp_min_bps,
    max(esp_max_bps) AS esp_max_bps,
    avg(esp_p95_bps) AS esp_p95_bps,
    min(esp_min_pps) AS esp_min_pps,
    max(esp_max_pps) AS esp_max_pps,
    avg(esp_p95_pps) AS esp_p95_pps,
    min(icmp_min_bps) AS icmp_min_bps,
    max(icmp_max_bps) AS icmp_max_bps,
    avg(icmp_p95_bps) AS icmp_p95_bps,
    min(icmp_min_pps) AS icmp_min_pps,
    max(icmp_max_pps) AS icmp_max_pps,
    avg(icmp_p95_pps) AS icmp_p95_pps
FROM flows.prefixes_proto_1h
WHERE time_received >= (NOW() - toIntervalDay(1))
GROUP BY
    prefix,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_ip_1d_mv
REFRESH EVERY 1 DAY APPEND TO flows.prefixes_ip_1d
AS SELECT
    prefix,
    dst_addr,
    toStartOfDay(time_received) AS time_received,
    quantile(0.95)(any_bytes) AS any_p95_bytes,
    quantile(0.95)(any_packets) AS any_p95_packets,
    quantile(0.95)(any_flows) AS any_p95_flows,
    max(any_bytes) AS any_max_bytes,
    max(any_packets) AS any_max_packets,
    max(any_flows) AS any_max_flows,
    quantile(0.95)(tcp_bytes) AS tcp_p95_bytes,
    quantile(0.95)(tcp_packets) AS tcp_p95_packets,
    quantile(0.95)(tcp_flows) AS tcp_p95_flows,
    max(tcp_bytes) AS tcp_max_bytes,
    max(tcp_packets) AS tcp_max_packets,
    max(tcp_flows) AS tcp_max_flows,
    quantile(0.95)(udp_bytes) AS udp_p95_bytes,
    quantile(0.95)(udp_packets) AS udp_p95_packets,
    quantile(0.95)(udp_flows) AS udp_p95_flows,
    max(udp_bytes) AS udp_max_bytes,
    max(udp_packets) AS udp_max_packets,
    max(udp_flows) AS udp_max_flows,
    quantile(0.95)(gre_bytes) AS gre_p95_bytes,
    quantile(0.95)(gre_packets) AS gre_p95_packets,
    quantile(0.95)(gre_flows) AS gre_p95_flows,
    max(gre_bytes) AS gre_max_bytes,
    max(gre_packets) AS gre_max_packets,
    max(gre_flows) AS gre_max_flows,
    quantile(0.95)(esp_bytes) AS esp_p95_bytes,
    quantile(0.95)(esp_packets) AS esp_p95_packets,
    quantile(0.95)(esp_flows) AS esp_p95_flows,
    max(esp_bytes) AS esp_max_bytes,
    max(esp_packets) AS esp_max_packets,
    max(esp_flows) AS esp_max_flows,
    quantile(0.95)(icmp_bytes) AS icmp_p95_bytes,
    quantile(0.95)(icmp_packets) AS icmp_p95_packets,
    quantile(0.95)(icmp_flows) AS icmp_p95_flows,
    max(icmp_bytes) AS icmp_max_bytes,
    max(icmp_packets) AS icmp_max_packets,
    max(icmp_flows) AS icmp_max_flows,
    min(any_min_bps) AS any_min_bps,
    max(any_max_bps) AS any_max_bps,
    avg(any_p95_bps) AS any_p95_bps,
    min(any_min_pps) AS any_min_pps,
    max(any_max_pps) AS any_max_pps,
    avg(any_p95_pps) AS any_p95_pps,
    min(tcp_min_bps) AS tcp_min_bps,
    max(tcp_max_bps) AS tcp_max_bps,
    avg(tcp_p95_bps) AS tcp_p95_bps,
    min(tcp_min_pps) AS tcp_min_pps,
    max(tcp_max_pps) AS tcp_max_pps,
    avg(tcp_p95_pps) AS tcp_p95_pps,
    min(udp_min_bps) AS udp_min_bps,
    max(udp_max_bps) AS udp_max_bps,
    avg(udp_p95_bps) AS udp_p95_bps,
    min(udp_min_pps) AS udp_min_pps,
    max(udp_max_pps) AS udp_max_pps,
    avg(udp_p95_pps) AS udp_p95_pps,
    min(gre_min_bps) AS gre_min_bps,
    max(gre_max_bps) AS gre_max_bps,
    avg(gre_p95_bps) AS gre_p95_bps,
    min(gre_min_pps) AS gre_min_pps,
    max(gre_max_pps) AS gre_max_pps,
    avg(gre_p95_pps) AS gre_p95_pps,
    min(esp_min_bps) AS esp_min_bps,
    max(esp_max_bps) AS esp_max_bps,
    avg(esp_p95_bps) AS esp_p95_bps,
    min(esp_min_pps) AS esp_min_pps,
    max(esp_max_pps) AS esp_max_pps,
    avg(esp_p95_pps) AS esp_p95_pps,
    min(icmp_min_bps) AS icmp_min_bps,
    max(icmp_max_bps) AS icmp_max_bps,
    avg(icmp_p95_bps) AS icmp_p95_bps,
    min(icmp_min_pps) AS icmp_min_pps,
    max(icmp_max_pps) AS icmp_max_pps,
    avg(icmp_p95_pps) AS icmp_p95_pps
FROM flows.prefixes_ip_1h
WHERE time_received >= (NOW() - toIntervalDay(1))
GROUP BY
    prefix,
    dst_addr,
    time_received;

CREATE MATERIALIZED VIEW IF NOT EXISTS flows.expression_metrics_1m_mv TO flows.expression_metrics_1m
AS SELECT
    expression_id,
    toStartOfMinute(time_received) AS time_received,
    sum(bytes) AS bytes,
    sum(packets) AS packets
FROM flows.expression_metrics_1m
GROUP BY
    expression_id,
    time_received;
