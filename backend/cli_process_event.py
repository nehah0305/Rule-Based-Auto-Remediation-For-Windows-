"""
cli_process_event.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Entry-point script invoked directly by Windows Task Scheduler
the instant a watched Windows Event ID is detected.

This script is intentionally lightweight and stateless:
  1. It polls the Windows Event Log for the single latest unprocessed event.
  2. Runs the full Root Cause Variant analysis pipeline (same as Flask/polling).
  3. Executes or enqueues the correct PowerShell remediation script.
  4. Writes all output to a unified log file shared with the Flask server,
     so the Flutter dashboard always shows a complete picture.
  5. Exits immediately — zero idle CPU usage.

Usage (invoked by Task Scheduler):
    python "C:\\path\\to\\backend\\cli_process_event.py"

Environment:
    Reads the same .env as app.py so no separate configuration is needed.
    Works even if Flask is not running.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

import os
import sys
import logging
import traceback
from datetime import datetime, timezone

# ── Ensure the backend package is importable regardless of CWD ──────────────
# Task Scheduler may set CWD to System32, so we anchor imports to this file's
# actual directory.
_BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
if _BACKEND_DIR not in sys.path:
    sys.path.insert(0, _BACKEND_DIR)

# ── Unified log file — shared with app.py so the dashboard shows everything ──
_DATA_DIR  = os.path.join(_BACKEND_DIR, 'data')
os.makedirs(_DATA_DIR, exist_ok=True)
_LOG_FILE  = os.path.join(_DATA_DIR, 'remediation_system.log')

# ── Configure logging to write to the shared unified log file ────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] [TASK-SCHEDULER] %(message)s',
    handlers=[
        logging.FileHandler(_LOG_FILE, encoding='utf-8'),
        logging.StreamHandler(sys.stdout),   # also visible if run manually
    ],
)
logger = logging.getLogger('cli_process_event')

# ── Crash log for silent background failures: captures any Python exception ──
_CRASH_LOG = os.path.join(_DATA_DIR, 'task_scheduler_crash.log')


def _write_crash_log(exc: Exception):
    """Append full traceback to the crash log so failures are never silent."""
    with open(_CRASH_LOG, 'a', encoding='utf-8') as f:
        ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        f.write(f'\n{"="*60}\n[{ts}] CRASH in cli_process_event.py\n')
        f.write(traceback.format_exc())
        f.write(f'{"="*60}\n')


def main():
    logger.info('━━━ Task Scheduler woke cli_process_event.py ━━━')

    # ── Lazy import here so any import-time errors are caught by our handler ──
    try:
        from dotenv import load_dotenv
        load_dotenv(os.path.join(_BACKEND_DIR, '..', '.env'))

        from db_init import init_db
        import event_log_monitor

    except Exception as e:
        logger.error(f'Import/init error: {e}')
        _write_crash_log(e)
        sys.exit(1)

    # ── Ensure the database schema is up to date ─────────────────────────────
    try:
        init_db()
    except Exception as e:
        logger.error(f'DB init error: {e}')
        _write_crash_log(e)
        sys.exit(1)

    # ── Run one immediate poll cycle ─────────────────────────────────────────
    # trigger_poll() uses the watermark so it only processes events that
    # arrived AFTER the last successful poll — no duplicate processing.
    try:
        count = event_log_monitor.trigger_poll()
        if count:
            logger.info(f'Poll complete — ingested and processed {count} new event(s).')
        else:
            logger.info('Poll complete — no new events found (watermark up-to-date).')
    except Exception as e:
        logger.error(f'Poll cycle error: {e}')
        _write_crash_log(e)
        sys.exit(1)

    logger.info('━━━ cli_process_event.py finished — exiting cleanly ━━━')
    sys.exit(0)


if __name__ == '__main__':
    try:
        main()
    except Exception as top_exc:
        # Absolute last-resort catch — ensures the crash log is always written
        _write_crash_log(top_exc)
        print(f'[FATAL] Unhandled exception: {top_exc}', file=sys.stderr)
        sys.exit(1)
