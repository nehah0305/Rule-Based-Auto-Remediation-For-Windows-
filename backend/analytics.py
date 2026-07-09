"""
analytics.py
Task 4 — observability/metrics for Phase 2 ML training data and the
dashboard's metrics panel. Pure read-only aggregation over the existing
`events` / `remediation_history` / `approval_requests` tables; no new
tables, no writes.
"""
from datetime import datetime, timedelta, timezone


def _conn():
    # Delegate to models' centralized factory so every connection — including
    # analytics reads racing the event-monitor's writes — gets WAL mode,
    # synchronous=NORMAL and a busy timeout instead of 'database is locked'.
    import models
    return models.get_connection()


# Statuses that represent an actual execution attempt (script really ran).
ATTEMPT_STATUSES = ('success', 'failed', 'error', 'rolled_back', 'verification_failed')
SUCCESS_STATUSES = ('success',)


def get_success_rate():
    """Success rate (%) over remediations that actually ran (excludes skipped/
    suppressed/pending_approval/rejected, which never executed a script)."""
    conn = _conn()
    try:
        c = conn.cursor()
        placeholders = ','.join('?' * len(ATTEMPT_STATUSES))
        c.execute(f'SELECT COUNT(*) FROM remediation_history WHERE status IN ({placeholders})',
                  ATTEMPT_STATUSES)
        total_attempts = c.fetchone()[0]

        placeholders = ','.join('?' * len(SUCCESS_STATUSES))
        c.execute(f'SELECT COUNT(*) FROM remediation_history WHERE status IN ({placeholders})',
                  SUCCESS_STATUSES)
        total_success = c.fetchone()[0]

        rate = round((total_success / total_attempts) * 100, 1) if total_attempts else 0.0
        return {
            'success_rate_pct': rate,
            'total_attempts': total_attempts,
            'total_successful': total_success,
        }
    finally:
        conn.close()


def get_mttr():
    """
    Mean Time To Remediation, in seconds: average time between the
    originating event's timestamp and the moment its remediation was
    confirmed successful (verified_at if the closed-loop verifier set it,
    else the history row's own timestamp for older/unverified rows).
    """
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('''
            SELECT e.timestamp, COALESCE(h.verified_at, h.timestamp)
            FROM remediation_history h
            JOIN events e ON h.event_row_id = e.id
            WHERE h.status = 'success' AND e.timestamp IS NOT NULL
        ''')
        deltas = []
        for event_ts, resolved_ts in c.fetchall():
            d = _safe_delta_seconds(event_ts, resolved_ts)
            if d is not None and d >= 0:
                deltas.append(d)

        if not deltas:
            return {'mttr_seconds': None, 'mttr_human': 'N/A', 'sample_size': 0}

        avg_seconds = sum(deltas) / len(deltas)
        return {
            'mttr_seconds': round(avg_seconds, 1),
            'mttr_human': _humanize_seconds(avg_seconds),
            'sample_size': len(deltas),
        }
    finally:
        conn.close()


def get_mttr_timeseries(days=14):
    """MTTR bucketed by day for the last N days, for a historical line chart."""
    conn = _conn()
    try:
        c = conn.cursor()
        since = (datetime.utcnow() - timedelta(days=days)).isoformat()
        c.execute('''
            SELECT e.timestamp, COALESCE(h.verified_at, h.timestamp)
            FROM remediation_history h
            JOIN events e ON h.event_row_id = e.id
            WHERE h.status = 'success' AND e.timestamp >= ?
            ORDER BY e.timestamp ASC
        ''', (since,))

        buckets = {}  # date_str -> list of deltas
        for event_ts, resolved_ts in c.fetchall():
            d = _safe_delta_seconds(event_ts, resolved_ts)
            if d is None or d < 0:
                continue
            date_str = _local_date_str(event_ts)
            if not date_str:
                continue
            buckets.setdefault(date_str, []).append(d)

        series = [
            {
                'date': date_str,
                'mttr_seconds': round(sum(vals) / len(vals), 1),
                'count': len(vals),
            }
            for date_str, vals in sorted(buckets.items())
        ]
        return series
    finally:
        conn.close()


def get_auto_vs_manual_ratio():
    """
    Of all remediation attempts that actually ran, how many were fully
    automatic (auto_remediate rule, no operator sign-off needed) vs. gated
    behind the new-event-type approval workflow.
    """
    conn = _conn()
    try:
        c = conn.cursor()
        placeholders = ','.join('?' * len(ATTEMPT_STATUSES))
        c.execute(f'SELECT COUNT(*) FROM remediation_history WHERE status IN ({placeholders})',
                  ATTEMPT_STATUSES)
        total = c.fetchone()[0]

        # Approved-via-gate attempts: history rows whose (event_row_id, rule_id)
        # pair also has a resolved approval_requests entry.
        c.execute('''
            SELECT COUNT(*) FROM remediation_history h
            WHERE h.status IN ({})
              AND EXISTS (
                  SELECT 1 FROM approval_requests ar
                  WHERE ar.event_row_id = h.event_row_id AND ar.rule_id = h.rule_id
              )
        '''.format(placeholders), ATTEMPT_STATUSES)
        manual_count = c.fetchone()[0]

        auto_count = total - manual_count
        return {
            'auto_count': auto_count,
            'manual_approval_count': manual_count,
            'total': total,
            'auto_pct': round((auto_count / total) * 100, 1) if total else 0.0,
        }
    finally:
        conn.close()


def get_metrics_summary(mttr_timeseries_days=14):
    """Single grouping payload for GET /api/metrics."""
    return {
        'success_rate': get_success_rate(),
        'mttr': get_mttr(),
        'mttr_timeseries': get_mttr_timeseries(days=mttr_timeseries_days),
        'auto_vs_manual': get_auto_vs_manual_ratio(),
        'generated_at': datetime.utcnow().isoformat(),
    }


def _safe_delta_seconds(start_iso, end_iso):
    try:
        start = _parse_iso(start_iso)
        end = _parse_iso(end_iso)
        if start is None or end is None:
            return None
        return (end - start).total_seconds()
    except Exception:
        return None


def _parse_iso(ts):
    if not ts:
        return None
    ts = str(ts).replace('Z', '+00:00')
    try:
        dt = datetime.fromisoformat(ts)
        # This system writes timestamps inconsistently: some naive (implicitly
        # UTC, e.g. datetime.utcnow().isoformat() throughout models.py) and
        # some tz-aware UTC (e.g. event_log_monitor's Get-WinEvent parsing).
        # Normalize both to naive UTC so subtraction is apples-to-apples.
        if dt.tzinfo is not None:
            dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
        return dt
    except ValueError:
        return None


def _local_date_str(ts):
    """
    Bucket label for the MTTR chart: the LOCAL calendar date of a stored
    (UTC) timestamp. Taking the raw string's [:10] prefix would bucket by UTC
    day, shifting evening events onto the wrong chart day for any timezone
    east of UTC.
    """
    dt = _parse_iso(ts)
    if dt is None:
        return None
    return dt.replace(tzinfo=timezone.utc).astimezone().date().isoformat()


def _humanize_seconds(seconds):
    seconds = int(seconds)
    if seconds < 60:
        return f'{seconds}s'
    minutes, secs = divmod(seconds, 60)
    if minutes < 60:
        return f'{minutes}m {secs}s'
    hours, mins = divmod(minutes, 60)
    return f'{hours}h {mins}m'
