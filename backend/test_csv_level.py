import csv
import os

CSV_PATH = os.path.join(os.path.dirname(__file__), 'data', 'errors_warnings.csv')

with open(CSV_PATH, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
    
    print(f"Total rows: {len(rows)}")
    print(f"\nFieldnames: {reader.fieldnames}")
    print(f"\nSample rows (first 10):")
    print("-" * 100)
    
    for i, row in enumerate(rows[:10]):
        print(f"Row {i+1}:")
        print(f"  ID: {row['id']}")
        print(f"  Event ID: {row['event_id']}")
        print(f"  Severity: {row['severity']}")
        print(f"  Level: {row['level']}")
        print()
    
    # Count levels
    error_count = sum(1 for r in rows if r.get('level', '').lower() == 'error')
    warning_count = sum(1 for r in rows if r.get('level', '').lower() == 'warning')
    unknown_count = sum(1 for r in rows if not r.get('level'))
    
    print("-" * 100)
    print(f"\nLevel Statistics:")
    print(f"  Errors: {error_count}")
    print(f"  Warnings: {warning_count}")
    print(f"  Unknown/Empty: {unknown_count}")

