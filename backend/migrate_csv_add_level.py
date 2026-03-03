"""
Migrate errors_warnings.csv to add the 'level' column.
This script reads the existing CSV and adds a 'level' column with empty values.
New events will populate this field correctly.
"""
import os
import csv
import shutil
from datetime import datetime

DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')
CSV_PATH = os.path.join(DATA_DIR, 'errors_warnings.csv')
BACKUP_PATH = os.path.join(DATA_DIR, f'errors_warnings_backup_{datetime.now().strftime("%Y%m%d_%H%M%S")}.csv')

def migrate_csv():
    if not os.path.exists(CSV_PATH):
        print(f"CSV file not found at {CSV_PATH}")
        return
    
    # Create backup
    shutil.copy2(CSV_PATH, BACKUP_PATH)
    print(f"✅ Created backup: {BACKUP_PATH}")
    
    # Read existing data
    rows = []
    needs_migration = False
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        old_fieldnames = reader.fieldnames

        # Check if 'level' already exists
        if 'level' in old_fieldnames:
            print("ℹ️  'level' column already exists, checking if values need to be populated...")
            needs_migration = True

        for row in reader:
            rows.append(row)
            # Check if any row has empty level
            if needs_migration and not row.get('level'):
                needs_migration = True
    
    print(f"✅ Read {len(rows)} existing rows")
    
    # Write with new column
    new_fieldnames = ['id', 'event_id', 'log_name', 'source', 'message', 'timestamp', 
                      'category', 'severity', 'description', 'recommended_action', 'level']
    
    with open(CSV_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=new_fieldnames)
        writer.writeheader()

        for row in rows:
            # Infer level from severity for existing rows
            severity = row.get('severity', '').lower()
            if severity in ['critical', 'high', 'error']:
                row['level'] = 'Error'
            elif severity in ['medium', 'low', 'warning', 'warn']:
                row['level'] = 'Warning'
            else:
                # Default to Warning if we can't determine
                row['level'] = 'Warning'

            writer.writerow({k: row.get(k, '') for k in new_fieldnames})
    
    print(f"✅ Migrated CSV with 'level' column")
    print(f"✅ Total rows: {len(rows)}")
    print(f"✅ New events will populate the 'level' field automatically")

if __name__ == '__main__':
    migrate_csv()
    print("\n✅ Migration complete!")

