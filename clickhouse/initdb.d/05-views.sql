CREATE VIEW IF NOT EXISTS flows.static_threshold_alerts_vw
AS WITH
    toStartOfMinute({date:DateTime}) AS datetime_rounded,
    threshold_rules AS
    (
        SELECT
            id,
            arrayJoin(prefixes) AS prefix,
            bandwidth_threshold,
            packet_threshold,
            duration
        FROM flows.rules
        WHERE type = 'threshold'
    ),
    prefixes_1m AS
    (
        SELECT *
        FROM flows.prefixes_proto_1m
        FINAL
        WHERE ((time_received >= (datetime_rounded - toIntervalMinute({max_duration:UInt64}))) AND (time_received <= datetime_rounded)) AND (prefix IN (
            SELECT prefix
            FROM threshold_rules
        ))
    ),
    aggregated AS
    (
        SELECT
            r.id,
            r.prefix AS prefix,
            r.bandwidth_threshold,
            r.packet_threshold,
            r.duration,
            groupArray(pm.time_received) AS times,
            groupArray((pm.any_bytes * 8) / 60) AS bps_values,
            groupArray(pm.any_packets / 60) AS pps_values,
            max((pm.any_bytes * 8) / 60) AS peak_bps,
            max(pm.any_packets / 60) AS peak_pps
        FROM prefixes_1m AS pm
        INNER JOIN threshold_rules AS r ON pm.prefix = r.prefix
        WHERE pm.time_received >= (datetime_rounded - toIntervalMinute(r.duration))
        GROUP BY
            r.id,
            r.prefix,
            r.bandwidth_threshold,
            r.packet_threshold,
            r.duration
    )
SELECT
    id,
    prefix,
    (bandwidth_threshold IS NOT NULL) AND (length(times) >= duration) AND arrayAll(x -> (x >= bandwidth_threshold), arraySlice(bps_values, -toInt32(duration))) AS bandwidth_alert,
    peak_bps,
    (packet_threshold IS NOT NULL) AND (length(times) >= duration) AND arrayAll(x -> (x >= packet_threshold), arraySlice(pps_values, -toInt32(duration))) AS packet_alert,
    peak_pps
FROM aggregated
WHERE bandwidth_alert OR packet_alert;

CREATE VIEW IF NOT EXISTS flows.dynamic_threshold_alerts_vw
AS WITH
    toStartOfMinute({date:DateTime}) AS datetime_rounded,
    datetime_rounded - toIntervalMinute(5) AS short_win,
    datetime_rounded - toIntervalHour(4) AS long_win,
    threshold_rules AS
    (
        SELECT
            id,
            arrayJoin(prefixes) AS prefix,
            zscore_sensitivity,
            zscore_target
        FROM flows.rules
        WHERE type = 'zscore'
    ),
    prefixes_stats AS
    (
        SELECT
            prefix,
            avgIf((any_bytes * 8) / 60, time_received >= short_win) AS short_avg_bps,
            avgIf(any_packets / 60, time_received >= short_win) AS short_avg_pps,
            maxIf((any_bytes * 8) / 60, time_received >= short_win) AS short_max_bps,
            maxIf(any_packets / 60, time_received >= short_win) AS short_max_pps,
            avgIf((any_bytes * 8) / 60, time_received < short_win) AS long_avg_bps,
            stddevPopStableIf((any_bytes * 8) / 60, time_received < short_win) AS long_stddev_bps,
            avgIf(any_packets / 60, time_received < short_win) AS long_avg_pps,
            stddevPopStableIf(any_packets / 60, time_received < short_win) AS long_stddev_pps,
            countIf(time_received < short_win) AS baseline_samples
        FROM flows.prefixes_proto_1m
        FINAL
        WHERE ((time_received >= long_win) AND (time_received <= datetime_rounded)) AND (prefix IN (
            SELECT prefix
            FROM threshold_rules
        ))
        GROUP BY prefix
        HAVING (baseline_samples >= 30) AND (long_avg_bps >= 1000000)
    ),
    computed_alerts AS
    (
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
            if(ps.long_stddev_bps > 0, (ps.short_avg_bps - ps.long_avg_bps) / ps.long_stddev_bps, 0) AS bps_zscore,
            if(ps.long_stddev_pps > 0, (ps.short_avg_pps - ps.long_avg_pps) / ps.long_stddev_pps, 0) AS pps_zscore,
            SensitivityLevelToZScore(r.zscore_sensitivity) AS threshold_zscore
        FROM prefixes_stats AS ps
        INNER JOIN threshold_rules AS r ON ps.prefix = r.prefix
    )
SELECT
    id,
    prefix,
    (zscore_target = 'bits') AND (bps_zscore >= threshold_zscore) AS bandwidth_alert,
    peak_bps,
    (zscore_target = 'packets') AND (pps_zscore >= threshold_zscore) AS packet_alert,
    peak_pps
FROM computed_alerts
WHERE bandwidth_alert OR packet_alert;
