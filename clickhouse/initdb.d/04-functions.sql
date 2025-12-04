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

CREATE FUNCTION IF NOT EXISTS NumToTcpFlagString AS (tcp_flag) ->
(
    transform(tcp_flag, [1, 2, 4, 8, 16, 32, 64, 128, 256, 512], ['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECN', 'CWR', 'NONCE', 'RESERVED'], toString(tcp_flag))
);

CREATE FUNCTION IF NOT EXISTS NumToTcpFlagsString AS (tcp_flags) ->
(
    if(tcp_flags = 0, 'EMPTY', arrayStringConcat(arrayMap(x -> NumToTcpFlagString(x), bitmaskToArray(tcp_flags)), '+'))
);

CREATE FUNCTION IF NOT EXISTS NumToForwardingStatusString AS (forwarding_status) ->
(
    transform(if(forwarding_status >= 64, bitShiftRight(forwarding_status, 7), forwarding_status), [0, 1, 2, 3], ['UNKNOWN', 'FORWARDED', 'DROPPED', 'CONSUMED'], toString(forwarding_status))
);

CREATE FUNCTION IF NOT EXISTS IPStringToNum AS (ip) ->
(
    if(isIPv4String(ip) = 1, toUInt128(IPv4StringToNumOrNull(ip)), reinterpretAsUInt128(reverse(IPv6StringToNumOrNull(dst_addr_str))))
);

CREATE FUNCTION IF NOT EXISTS NumToProtoString AS (proto) ->
(
    dictGetOrDefault('flows.protocols', 'name', proto, toString(proto))
);

CREATE FUNCTION IF NOT EXISTS SensitivityLevelToZScore AS (sensitivity) ->
(
    transform(sensitivity, ['low', 'medium', 'high'], [4, 3, 2], 3)
);


CREATE FUNCTION IF NOT EXISTS FireStaticThresholdAlert AS (ip_prefix, threshold, target, duration, `datetime`) ->
(
    WITH
        toDateTime(`datetime`) AS datetime_rounded,
        if(target = 'bits', bytes * 8 / 60, packets / 60) AS metric
        SELECT
            countIf(metric >= threshold) = count(*)
        FROM flows.prefixes_total_1m FINAL
        WHERE
            prefix = ip_prefix AND
            time_received BETWEEN datetime_rounded - duration AND datetime_rounded
);


-- the formula for calculating the dynamic threshold is based on:
-- https://developers.cloudflare.com/magic-network-monitoring/rules/dynamic-threshold/#how-the-dynamic-rule-threshold-is-calculated

-- sensitivity levels:
-- low: z-score >= 4
-- medium: z-score >= 3
-- high: z-score >= 2

-- target: bits or packets


CREATE FUNCTION IF NOT EXISTS FireDynamicThresholdAlert AS (ip_prefix, sensitivity, target, `datetime`) ->
(
    WITH
        toDateTime(`datetime`) AS datetime_rounded,
        datetime_rounded - INTERVAL 5 MINUTE AS short_win,
        datetime_rounded - INTERVAL 4 HOUR AS long_win,
        if(target = 'bits', bytes * 8 / 60, packets / 60) AS metric,
        SensitivityLevelToZScore(sensitivity) AS z_threshold,
        stats AS (
            SELECT
                avgIf(metric, time_received >= short_win) AS short_avg,
                avg(metric) AS long_avg,
                stddevPopStable(metric) AS long_stddev
            FROM flows.prefixes_total_1m FINAL
            WHERE
                prefix = ip_prefix AND
                time_received BETWEEN long_win AND datetime_rounded
        )
        SELECT 
            if(stats.long_stddev = 0, false, (stats.short_avg - stats.long_avg) / stats.long_stddev >= z_threshold)
        FROM stats
);
