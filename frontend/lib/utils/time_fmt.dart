/// Central timestamp handling for values coming from the backend API.
///
/// The backend stores and emits UTC timestamps, but in mixed shapes: naive
/// ISO strings from `datetime.utcnow()` (no offset — events, history,
/// approvals, simulations) and tz-aware strings ending in 'Z' or '+00:00'
/// (Windows Event Log ingestion, monitor status). Dart's [DateTime.parse]
/// treats an offsetless string as *local* wall time, which silently rendered
/// UTC values as if they were local — hours off from the system clock, and
/// only in the tabs whose data happened to be offsetless. Every screen must
/// go through these helpers instead of calling DateTime.parse directly on
/// server-supplied values.
library;

final RegExp _explicitOffset = RegExp(r'(Z|z|[+-]\d{2}:?\d{2})$');

/// Parse a backend timestamp into a [DateTime] in the system's local zone.
/// Offsetless strings are interpreted as UTC. Date-only strings (no time
/// component) are calendar labels, not instants — parsed as-is. Returns null
/// if unparseable.
DateTime? parseServerTime(String? ts) {
  if (ts == null || ts.trim().isEmpty) return null;
  final s = ts.trim();
  try {
    // A ':' can only appear in a time (or offset) component; without one the
    // string is date-only and appending 'Z' would make it invalid ISO 8601.
    final needsUtcMarker = s.contains(':') && !_explicitOffset.hasMatch(s);
    final dt = DateTime.parse(needsUtcMarker ? '${s}Z' : s);
    return dt.toLocal();
  } catch (_) {
    return null;
  }
}

/// Format a backend timestamp in local time: 'YYYY-MM-DD HH:MM' with the
/// default length of 16, 'YYYY-MM-DD HH:MM:SS' with 19. Falls back to the
/// raw string (truncated) when unparseable, or [fallback] when null/empty.
String fmtServerTime(String? ts, {int length = 16, String fallback = '—'}) {
  if (ts == null || ts.trim().isEmpty) return fallback;
  final dt = parseServerTime(ts);
  if (dt == null) return ts.length > length ? ts.substring(0, length) : ts;
  final s = dt.toString();
  return s.length > length ? s.substring(0, length) : s;
}
