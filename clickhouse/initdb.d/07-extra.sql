
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


CREATE TABLE IF NOT EXISTS flows.prefixes_all_total_1m
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


CREATE MATERIALIZED VIEW IF NOT EXISTS flows.prefixes_all_total_1m_mv TO flows.prefixes_all_total_1m AS
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
