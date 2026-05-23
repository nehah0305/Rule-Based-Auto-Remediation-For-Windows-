import sqlite3
conn = sqlite3.connect('backend/rules.db')
conn.row_factory = sqlite3.Row

print('=== LATEST HISTORY ===')
rows = conn.execute(
    'SELECT h.id, h.event_row_id, h.rule_id, h.status, h.timestamp, '
    'SUBSTR(h.output,1,120) as out FROM remediation_history h '
    'ORDER BY h.id DESC LIMIT 8'
).fetchall()
for r in rows:
    print(dict(r))

print()
print('=== LATEST EVENT 1000s ===')
rows = conn.execute(
    "SELECT id, event_id, source, timestamp, needs_manual_review "
    "FROM events WHERE event_id=1000 ORDER BY id DESC LIMIT 5"
).fetchall()
for r in rows:
    print(dict(r))

conn.close()
