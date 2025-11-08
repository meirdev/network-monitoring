CREATE TABLE IF NOT EXISTS flows.prefixes
(
    prefix LowCardinality(String)
)
ENGINE = ReplacingMergeTree()
PRIMARY KEY prefix;


CREATE DICTIONARY IF NOT EXISTS dictionaries.prefixes (
    id String,
    prefix String
)
PRIMARY KEY id
LAYOUT(IP_TRIE)
SOURCE (CLICKHOUSE(query 'SELECT prefix, prefix FROM flows.prefixes FINAL' user 'default' password 'password'))
LIFETIME(300);


CREATE TABLE IF NOT EXISTS flows.prefixes_total_1m
(
    prefix LowCardinality(String),

    time_received DateTime,

    bytes UInt64,
    packets UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toDate(time_received)
ORDER BY (prefix, time_received)
TTL toDate(time_received) + INTERVAL 30 DAY;


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_total_1m_mv TO flows.prefixes_total_1m AS
    SELECT
        dictGetStringOrDefault('dictionaries.prefixes', 'prefix', toIPv6(dst_addr), '') AS prefix,

        toStartOfMinute(time_received) AS time_received,

        sum(bytes) AS bytes,
        sum(packets) AS packets
    FROM flows.grafana
    WHERE prefix <> ''
    GROUP BY prefix, time_received;


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
