CREATE VIEW IF NOT EXISTS flows.static_threshold_alerts_vw AS (
    WITH
        toDateTime({date:DateTime}) AS datetime_rounded,
        threshold_rules AS (
            SELECT
                id,
                arrayJoin(prefixes) AS prefix,
                bandwidth_threshold,
                packet_threshold,
                duration
            FROM flows.rules
            WHERE type = 'threshold'
        ),
        prefixes_1m AS (
            SELECT *
            FROM flows.prefixes_total_1m FINAL
            WHERE 
                time_received BETWEEN datetime_rounded - toIntervalMinute({max_duration:UInt64}) AND datetime_rounded
                AND prefix IN (SELECT prefix FROM threshold_rules)
        )
    SELECT
        r.id,
        r.prefix AS prefix,
        any(r.bandwidth_threshold) IS NOT NULL AND
            countIf(pm.bytes * 8 / 60 >= r.bandwidth_threshold 
                AND pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)) 
            = countIf(pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)) AS bandwidth_alert,
        max(pm.bytes * 8 / 60) AS peak_bps,
        any(r.packet_threshold) IS NOT NULL AND 
            countIf(pm.packets / 60 >= r.packet_threshold 
                AND pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)) 
            = countIf(pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)) AS packet_alert,
        max(pm.packets / 60) AS peak_pps
    FROM prefixes_1m pm
    INNER JOIN threshold_rules r ON pm.prefix = r.prefix
    GROUP BY r.id, r.prefix
    HAVING bandwidth_alert OR packet_alert
);


CREATE VIEW IF NOT EXISTS flows.dynamic_threshold_alerts_vw AS (
    WITH
        toDateTime({date:DateTime}) AS datetime_rounded,
        datetime_rounded - INTERVAL 5 MINUTE AS short_win,
        datetime_rounded - INTERVAL 4 HOUR AS long_win,
        threshold_rules AS (
            SELECT
                id,
                arrayJoin(prefixes) AS prefix,
                zscore_sensitivity,
                zscore_target
            FROM flows.rules
            WHERE type = 'zscore'
        ),
        prefixes_1m AS (
            SELECT
                prefix,
                avgIf(bytes * 8 / 60, time_received >= short_win) AS short_avg_bps,
                maxIf(bytes * 8 / 60, time_received >= short_win) AS peak_bps,
                avg(bytes * 8 / 60) AS long_avg_bps,
                stddevPopStable(bytes * 8 / 60) AS long_stddev_bps,
                avgIf(packets / 60, time_received >= short_win) AS short_avg_pps,
                maxIf(packets / 60, time_received >= short_win) AS peak_pps,
                avg(packets / 60) AS long_avg_pps,
                stddevPopStable(packets / 60) AS long_stddev_pps
            FROM flows.prefixes_total_1m FINAL
            WHERE
                time_received BETWEEN long_win AND datetime_rounded AND
                prefix IN (SELECT prefix FROM threshold_rules)
            GROUP BY prefix
        )
    SELECT
        r.id,
        r.prefix AS prefix,
        if(r.zscore_target = 'bandwidth' AND pm.long_stddev_bps > 0,
        (pm.short_avg_bps - pm.long_avg_bps) / pm.long_stddev_bps >= SensitivityLevelToZScore(r.zscore_sensitivity),
        false) AS bandwidth_alert,
        peak_bps,
        if(r.zscore_target = 'packets' AND pm.long_stddev_pps > 0,
        (pm.short_avg_pps - pm.long_avg_pps) / pm.long_stddev_pps >= SensitivityLevelToZScore(r.zscore_sensitivity),
        false) AS packet_alert,
        peak_pps
    FROM prefixes_1m pm
    INNER JOIN threshold_rules r ON pm.prefix = r.prefix
    WHERE bandwidth_alert OR packet_alert
);


CREATE VIEW IF NOT EXISTS flows.advanced_ddos_alerts_vw AS (
    WITH
        toDateTime({date:DateTime}) AS datetime_rounded,
        transform({sensitivity:String}, ['low', 'medium', 'high'], [3.0, 2.0, 1.5], 1.5) AS sensitivity_value,
        threshold_rules AS (
            SELECT
                id,
                arrayJoin(prefixes) AS prefix
            FROM flows.rules
            WHERE type = 'advanced_ddos'
        ),
        prefixes_proto_1d AS (
            SELECT
            	prefix,
                proto,
                floor(avg(p95_bytes)) * 8 / 60 AS avg_bps,
                floor(avg(p95_packets)) / 60 AS avg_pps,
                floor(avg(p95_flows)) / 60 AS avg_fps
            FROM flows.prefixes_proto_profile_1d
            WHERE
                time_received BETWEEN datetime_rounded - INTERVAL 7 DAY AND datetime_rounded
                AND prefix IN (SELECT prefix FROM threshold_rules)
            GROUP BY prefix, proto
        )
        SELECT
            r.id AS id,
        	p1m.time_received AS time_received,
        	p1m.prefix AS prefix,
            p1m.`protoMap.proto` AS proto,
            p1m.`protoMap.bytes` * 8 / 60 AS current_bps,
            p1m.`protoMap.packets` / 60 AS current_pps,
            p1m.`protoMap.flows` / 60 AS current_fps,
            avg_bps * sensitivity_value AS recommend_bps,
            avg_pps * sensitivity_value AS recommend_pps,
            avg_fps * sensitivity_value AS recommend_fps,
            current_bps >= recommend_bps AS bps_alert,
            current_pps >= recommend_pps AS pps_alert,
            current_fps >= recommend_fps AS fps_alert
        FROM flows.prefixes_proto_profile_1m p1m FINAL
        ARRAY JOIN
            protoMap.proto,
            protoMap.bytes,
            protoMap.packets,
            protoMap.flows
        INNER ANY JOIN prefixes_proto_1d p1d ON (p1m.prefix = p1d.prefix AND p1m.`protoMap.proto` = p1d.proto)
        INNER JOIN threshold_rules r ON p1m.prefix = r.prefix
        WHERE 
            p1m.time_received BETWEEN datetime_rounded - INTERVAL 1 MINUTE AND datetime_rounded AND
            (bps_alert OR pps_alert OR fps_alert)
);
