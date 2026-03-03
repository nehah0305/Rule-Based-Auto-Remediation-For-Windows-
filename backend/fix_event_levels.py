"""
Fix event levels by querying Windows Event Log for actual level information.
This script reads the CSV and updates the level field based on actual Windows Event Log data.
"""
import os
import csv
import subprocess
import json
import shutil
from datetime import datetime

DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')
CSV_PATH = os.path.join(DATA_DIR, 'errors_warnings.csv')
BACKUP_PATH = os.path.join(DATA_DIR, f'errors_warnings_backup_fix_{datetime.now().strftime("%Y%m%d_%H%M%S")}.csv')

def get_event_level_from_windows(event_id, log_name, source):
    """Query Windows Event Log to get the actual level for an event."""
    try:
        # PowerShell command to get event level
        ps_command = f"""
        $events = Get-WinEvent -FilterHashtable @{{LogName='{log_name}'; Id={event_id}}} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($events) {{
            $event = $events[0]
            @{{
                Level = $event.Level
                LevelDisplayName = $event.LevelDisplayName
            }} | ConvertTo-Json
        }}
        """
        
        result = subprocess.run(
            ['powershell', '-NoProfile', '-Command', ps_command],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout.strip())
            return data.get('LevelDisplayName', 'Warning')
        
    except Exception as e:
        pass
    
    return None

def fix_levels():
    if not os.path.exists(CSV_PATH):
        print(f"CSV file not found at {CSV_PATH}")
        return
    
    # Create backup
    shutil.copy2(CSV_PATH, BACKUP_PATH)
    print(f"✅ Created backup: {BACKUP_PATH}")
    
    # Read existing data
    rows = []
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    
    print(f"✅ Read {len(rows)} existing rows")
    print(f"🔍 Querying Windows Event Log for actual levels...")
    
    # Cache for event levels to avoid repeated queries
    level_cache = {}
    
    # Update levels
    updated_count = 0
    error_count = 0
    warning_count = 0
    
    for i, row in enumerate(rows):
        event_id = row.get('event_id')
        log_name = row.get('log_name')
        source = row.get('source')
        
        # Create cache key
        cache_key = f"{log_name}:{event_id}:{source}"
        
        # Check cache first
        if cache_key in level_cache:
            level = level_cache[cache_key]
        else:
            # Query Windows Event Log
            level = get_event_level_from_windows(event_id, log_name, source)
            if level:
                level_cache[cache_key] = level
        
        # Update row
        if level:
            row['level'] = level
            updated_count += 1
            
            if level.lower() == 'error':
                error_count += 1
            elif level.lower() == 'warning':
                warning_count += 1
        
        # Progress indicator
        if (i + 1) % 100 == 0:
            print(f"  Processed {i + 1}/{len(rows)} rows...")
    
    print(f"✅ Updated {updated_count} rows with actual levels from Windows Event Log")
    
    # Write updated data
    fieldnames = ['id', 'event_id', 'log_name', 'source', 'message', 'timestamp', 
                  'category', 'severity', 'description', 'recommended_action', 'level']
    
    with open(CSV_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        
        for row in rows:
            writer.writerow({k: row.get(k, '') for k in fieldnames})
    
    print(f"✅ Saved updated CSV")
    print(f"\n📊 Level Statistics:")
    print(f"  Errors: {error_count}")
    print(f"  Warnings: {warning_count}")
    print(f"  Total Updated: {updated_count}")

if __name__ == '__main__':
    print("=" * 80)
    print("Fixing Event Levels from Windows Event Log")
    print("=" * 80)
    fix_levels()
    print("\n✅ Fix complete!")
    print("=" * 80)

