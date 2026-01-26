CREATE VIEW IF NOT EXISTS flows.static_threshold_alerts_vw AS (
    WITH
        toStartOfMinute({date:DateTime}) AS datetime_rounded,
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
        ),
        aggregated AS (
            SELECT
                r.id,
                r.prefix AS prefix,
                r.bandwidth_threshold,
                r.packet_threshold,
                r.duration,
                groupArray(pm.time_received) AS times,
                groupArray(pm.bytes * 8 / 60) AS bps_values,
                groupArray(pm.packets / 60) AS pps_values,
                max(pm.bytes * 8 / 60) AS peak_bps,
                max(pm.packets / 60) AS peak_pps
            FROM prefixes_1m pm
            INNER JOIN threshold_rules r ON pm.prefix = r.prefix
            WHERE pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)
            GROUP BY r.id, r.prefix, r.bandwidth_threshold, r.packet_threshold, r.duration
        )
    SELECT
        id,
        prefix,
        bandwidth_threshold IS NOT NULL
            AND length(times) >= duration
            AND arrayAll(x -> x >= bandwidth_threshold, arraySlice(bps_values, -toInt32(duration))) AS bandwidth_alert,
        peak_bps,
        packet_threshold IS NOT NULL
            AND length(times) >= duration
            AND arrayAll(x -> x >= packet_threshold, arraySlice(pps_values, -toInt32(duration))) AS packet_alert,
        peak_pps
    FROM aggregated
    WHERE bandwidth_alert OR packet_alert
);

-- https://developers.cloudflare.com/magic-network-monitoring/rules/dynamic-threshold/#how-the-dynamic-rule-threshold-is-calculated

CREATE VIEW IF NOT EXISTS flows.dynamic_threshold_alerts_vw AS (
    WITH
        toStartOfMinute({date:DateTime}) AS datetime_rounded,
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
        prefixes_stats AS (
            SELECT
                prefix,
                avgIf(bytes * 8 / 60, time_received >= short_win) AS short_avg_bps,
                avgIf(packets / 60, time_received >= short_win) AS short_avg_pps,
                maxIf(bytes * 8 / 60, time_received >= short_win) AS short_max_bps,
                maxIf(packets / 60, time_received >= short_win) AS short_max_pps,
                avgIf(bytes * 8 / 60, time_received < short_win) AS long_avg_bps,
                stddevPopStableIf(bytes * 8 / 60, time_received < short_win) AS long_stddev_bps,
                avgIf(packets / 60, time_received < short_win) AS long_avg_pps,
                stddevPopStableIf(packets / 60, time_received < short_win) AS long_stddev_pps,
                countIf(time_received < short_win) AS baseline_samples
            FROM flows.prefixes_total_1m FINAL
            WHERE
                time_received BETWEEN long_win AND datetime_rounded
                AND prefix IN (SELECT prefix FROM threshold_rules)
            GROUP BY prefix
            HAVING
                baseline_samples >= 30
                AND long_avg_bps >= 1000000  -- at least 1 Mbps average
        ),
        computed_alerts AS (
            SELECT
                r.id,
                r.prefix AS prefix,
                r.zscore_target,
                ps.short_max_bps AS peak_bps,
                ps.short_max_pps AS peak_pps,
                ps.short_avg_bps,
                ps.short_avg_pps,
                ps.long_avg_bps,
                ps.long_stddev_bps,
                ps.long_avg_pps,
                ps.long_stddev_pps,
                if(ps.long_stddev_bps > 0,
                   (ps.short_avg_bps - ps.long_avg_bps) / ps.long_stddev_bps,
                   0) AS bps_zscore,
                if(ps.long_stddev_pps > 0,
                   (ps.short_avg_pps - ps.long_avg_pps) / ps.long_stddev_pps,
                   0) AS pps_zscore,
                SensitivityLevelToZScore(r.zscore_sensitivity) AS threshold_zscore
            FROM prefixes_stats ps
            INNER JOIN threshold_rules r ON ps.prefix = r.prefix
        )
    SELECT
        id,
        prefix,
        zscore_target = 'bits' AND bps_zscore >= threshold_zscore AS bandwidth_alert,
        peak_bps,
        zscore_target = 'packets' AND pps_zscore >= threshold_zscore AS packet_alert,
        peak_pps
    FROM computed_alerts
    WHERE bandwidth_alert OR packet_alert
);


CREATE VIEW IF NOT EXISTS flows.advanced_ddos_alerts_vw AS (
    WITH
        toStartOfMinute({date:DateTime}) AS datetime_rounded,
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
                p95_bytes * 8 / 60 AS prev_week_bps,
                p95_packets / 60 AS prev_week_pps,
                p95_flows / 60 AS prev_week_fps
            FROM flows.prefixes_proto_profile_1d
            WHERE
                time_received = toStartOfDay(datetime_rounded) - INTERVAL 7 DAY
                AND prefix IN (SELECT prefix FROM threshold_rules)
        )
        SELECT
            r.id AS id,
        	p1m.time_received AS time_received,
        	p1m.prefix AS prefix,
            p1m.`protoMap.proto` AS proto,
            p1m.`protoMap.bytes` * 8 / 60 AS current_bps,
            p1m.`protoMap.packets` / 60 AS current_pps,
            p1m.`protoMap.flows` / 60 AS current_fps,
            prev_week_bps * sensitivity_value AS recommend_bps,
            prev_week_pps * sensitivity_value AS recommend_pps,
            prev_week_fps * sensitivity_value AS recommend_fps,
            current_bps >= recommend_bps AS bps_alert,
            current_pps >= recommend_pps AS pps_alert,
            current_fps >= recommend_fps AS fps_alert
        FROM flows.prefixes_proto_profile_1m p1m FINAL
        ARRAY JOIN
            protoMap.proto,
            protoMap.bytes,
            protoMap.packets,
            protoMap.flows
        INNER JOIN prefixes_proto_1d p1d ON (p1m.prefix = p1d.prefix AND p1m.`protoMap.proto` = p1d.proto)
        INNER JOIN threshold_rules r ON p1m.prefix = r.prefix
        WHERE p1m.time_received = datetime_rounded AND (bps_alert OR pps_alert OR fps_alert)
);
