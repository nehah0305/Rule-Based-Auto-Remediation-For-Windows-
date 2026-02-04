#!/usr/bin/env python3
"""
Script to populate rules from the windows_error_events.json file.
This creates rules for all events marked as auto_remediate_candidate.
"""

import sys
import os

# Add the backend directory to the path
sys.path.insert(0, os.path.dirname(__file__))

from db_init import init_db
import models

def main():
    print("Initializing database...")
    init_db()
    
    print("\nLoading event definitions from JSON...")
    definitions = models.load_event_definitions()
    print(f"Found {len(definitions)} event definitions")
    
    # Count how many are auto-remediate candidates
    candidates = [d for d in definitions if d.get('auto_remediate_candidate', False)]
    print(f"Found {len(candidates)} events marked as auto-remediate candidates")
    
    if len(candidates) == 0:
        print("No auto-remediate candidates found. Exiting.")
        return
    
    print("\nDo you want to:")
    print("1. Add new rules (keep existing rules)")
    print("2. Replace all existing rules")
    choice = input("Enter choice (1 or 2): ").strip()
    
    overwrite = choice == "2"
    
    if overwrite:
        confirm = input("This will DELETE all existing rules. Are you sure? (yes/no): ").strip().lower()
        if confirm != "yes":
            print("Cancelled.")
            return
    
    print("\nPopulating rules...")
    count = models.populate_rules_from_json(overwrite=overwrite)
    
    print(f"\n✓ Successfully created {count} rules!")
    print("\nYou can now:")
    print("1. View the rules in the web dashboard at http://localhost:5000")
    print("2. Enable auto-remediation for specific rules")
    print("3. Add remediation scripts to the rules")
    
    # Show summary of created rules
    if count > 0:
        print("\nCreated rules summary:")
        rules = models.get_rules()
        for r in rules[-count:]:  # Show last 'count' rules
            print(f"  - {r[1]} (Event ID: {r[2]}, Source: {r[3]}, Severity: {r[8]})")

if __name__ == '__main__':
    main()

