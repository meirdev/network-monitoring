CREATE FUNCTION IF NOT EXISTS BytesToIPString AS (addr) ->
(
    -- if the first 12 bytes are zero, then it's an IPv4 address, otherwise it's an IPv6 address
    if(reinterpretAsUInt128(substring(reverse(addr), 1, 12)) = 0, IPv4NumToString(reinterpretAsUInt32(substring(reverse(addr), 13, 4))), IPv6NumToString(addr))
);

CREATE FUNCTION IF NOT EXISTS NumToFlowTypeString AS (type) ->
(
    transform(type, [0, 1, 2, 3, 4], ['UNKNOWN', 'SFLOW_5', 'NETFLOW_V5', 'NETFLOW_V9', 'IPFIX'], toString(type))
);

CREATE FUNCTION IF NOT EXISTS NumToETypeString AS (etype) ->
(
    transform(etype, [0x800, 0x806, 0x86dd], ['IPv4', 'ARP', 'IPv6'], toString(etype))
);

CREATE FUNCTION IF NOT EXISTS NumToTcpFlagsString AS (tcp_flags) ->
(
    if(tcp_flags = 0, 'EMPTY', arrayStringConcat(arrayMap(x -> transform(x, [1, 2, 4, 8, 16, 32, 64, 128, 256, 512], ['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECN', 'CWR', 'NONCE', 'RESERVED'], toString(x)), bitmaskToArray(tcp_flags)), '+'))
);

CREATE FUNCTION IF NOT EXISTS NumToForwardingStatusString AS (forwarding_status) ->
(
    transform(if(forwarding_status >= 64, bitShiftRight(forwarding_status, 7), forwarding_status), [0, 1, 2, 3], ['UNKNOWN', 'FORWARDED', 'DROPPED', 'CONSUMED'], toString(forwarding_status))
);

CREATE FUNCTION IF NOT EXISTS IPStringToNum AS (ip) ->
(
    if(position(ip, '.') <> 0, toUInt128(IPv4StringToNum(ip)), toUInt128(IPv6StringToNum(ip)))
);

CREATE FUNCTION IF NOT EXISTS NumToProtoString AS (proto) ->
(
    dictGetOrDefault('flows.protocols', 'name', proto, toString(proto))
);


CREATE FUNCTION IF NOT EXISTS fireStaticBpsThresholdAlert AS (ip_prefix, threshold, duration, `datetime`) ->
(
    WITH toDateTime(`datetime`) AS datetime_rounded,
    result AS (
        SELECT
            bytes * 8 / 60 AS bps,
            bps >= threshold AS is_exceeded
        FROM flows.prefixes_total_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_received >= datetime_rounded - duration AND
            time_received <= datetime_rounded
    )
    SELECT countIf(is_exceeded = true) = date_diff('minute', datetime_rounded - duration, datetime_rounded) FROM result
);


CREATE FUNCTION IF NOT EXISTS fireStaticPpsThresholdAlert AS (ip_prefix, threshold, duration, `datetime`) ->
(
    WITH toDateTime(`datetime`) AS datetime_rounded,
    result AS (
        SELECT
            packets / 60 AS pps,
            pps >= threshold AS is_exceeded
        FROM flows.prefixes_total_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_received >= datetime_rounded - duration AND
            time_received <= datetime_rounded
    )
    SELECT countIf(is_exceeded = true) = date_diff('minute', datetime_rounded - duration, datetime_rounded) FROM result
);


-- the formula for calculating the dynamic threshold is based on:
-- https://developers.cloudflare.com/magic-network-monitoring/rules/dynamic-threshold/#how-the-dynamic-rule-threshold-is-calculated

-- sensitivity levels:
-- low: z-score >= 4
-- medium: z-score >= 3
-- high: z-score >= 2


CREATE FUNCTION IF NOT EXISTS fireDynamicBpsThresholdAlert AS (ip_prefix, sensitivity, `datetime`) ->
(
    WITH toDateTime(`datetime`) AS datetime_rounded,
    short_window AS (
        SELECT
            avg(bytes * 8 / 60) AS avg_bps
        FROM flows.prefixes_total_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_received >= datetime_rounded - INTERVAL 5 MINUTE AND
            time_received <= datetime_rounded
    ),
    long_window AS (
        SELECT
            stddevPopStable(bytes * 8 / 60) AS stddev_bps,
            avg(bytes * 8 / 60) AS avg_bps
        FROM flows.prefixes_total_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_received >= datetime_rounded - INTERVAL 4 HOUR AND
            time_received <= datetime_rounded
    ),
    result AS (
        SELECT
            (short_window.avg_bps - long_window.avg_bps) / long_window.stddev_bps AS z_score
        FROM short_window, long_window
    )
    SELECT
        (
            (sensitivity = 'low' AND result.z_score >= 4) OR
            (sensitivity = 'medium' AND result.z_score >= 3) OR
            (sensitivity = 'high' AND result.z_score >= 2)
        )
    FROM result
);


CREATE FUNCTION IF NOT EXISTS fireDynamicPpsThresholdAlert AS (ip_prefix, sensitivity, `datetime`) ->
(
    WITH toDateTime(`datetime`) AS datetime_rounded,
    short_window AS (
        SELECT
            avg(packets / 60) AS avg_pps
        FROM flows.prefixes_total_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_received >= datetime_rounded - INTERVAL 5 MINUTE AND
            time_received <= datetime_rounded
    ),
    long_window AS (
        SELECT
            stddevPopStable(packets / 60) AS stddev_pps,
            avg(packets / 60) AS avg_pps
        FROM flows.prefixes_total_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_received >= datetime_rounded - INTERVAL 4 HOUR AND
            time_received <= datetime_rounded
    ),
    result AS (
        SELECT
            (short_window.avg_pps - long_window.avg_pps) / long_window.stddev_pps AS z_score
        FROM short_window, long_window
    )
    SELECT
        (
            (sensitivity = 'low' AND result.z_score >= 4) OR
            (sensitivity = 'medium' AND result.z_score >= 3) OR
            (sensitivity = 'high' AND result.z_score >= 2)
        )
    FROM result
);
