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
        any(r.bandwidth_threshold) IS NOT NULL AND
            countIf(pm.bytes * 8 / 60 >= r.bandwidth_threshold 
                AND pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)) 
            = countIf(pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)) AS bandwidth_alert,
        any(r.packet_threshold) IS NOT NULL AND 
            countIf(pm.packets / 60 >= r.packet_threshold 
                AND pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)) 
            = countIf(pm.time_received >= datetime_rounded - toIntervalMinute(r.duration)) AS packet_alert
    FROM prefixes_1m pm
    INNER JOIN threshold_rules r ON pm.prefix = r.prefix
    GROUP BY r.id
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
                avg(bytes * 8 / 60) AS long_avg_bps,
                stddevPopStable(bytes * 8 / 60) AS long_stddev_bps,
                avgIf(packets / 60, time_received >= short_win) AS short_avg_pps,
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
        if(r.zscore_target = 'bandwidth' AND pm.long_stddev_bps > 0,
        (pm.short_avg_bps - pm.long_avg_bps) / pm.long_stddev_bps >= SensitivityLevelToZScore(r.zscore_sensitivity),
        false) AS bandwidth_alert,
        if(r.zscore_target = 'packets' AND pm.long_stddev_pps > 0,
        (pm.short_avg_pps - pm.long_avg_pps) / pm.long_stddev_pps >= SensitivityLevelToZScore(r.zscore_sensitivity),
        false) AS packet_alert
    FROM prefixes_1m pm
    INNER JOIN threshold_rules r ON pm.prefix = r.prefix
    WHERE bandwidth_alert OR packet_alert
);
