"""
Shared pytest fixtures for the backend test suite (Task 5).

Isolation strategy: app.py runs `init_db()` and (conditionally) starts the
real Windows Event Log polling thread at MODULE IMPORT TIME, and every
models.py function reads the module-level `models.DB_PATH` global on every
call rather than a connection passed in. A literal `sqlite3.connect(':memory:')`
doesn't work here because models._conn() opens a brand-new connection per
call — an in-memory DB dies the instant that connection closes, so nothing
would ever persist between calls. Instead, each test session gets its own
throwaway *file-backed* SQLite DB, and `models.DB_PATH` / `db_init.DB_PATH`
are monkeypatched to point at it BEFORE `app` is ever imported, so the
import-time `init_db()` call (and everything after it) operates on the
disposable test DB instead of the real backend/rules.db.

`USE_TASK_SCHEDULER=true` is set before import so app.py's module-level
`event_log_monitor.start_monitor()` call is skipped — tests must never spin
up a real background thread polling the actual Windows Event Log.
"""
import os
import sys
import tempfile
import time as _time_module
import threading
from unittest.mock import MagicMock

import pytest

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

# models.py's `import time` is the *same* module object as this one (Python
# modules are process-wide singletons) — captured here, before anything ever
# monkeypatches time.sleep, so tests that need a short *real* delay (instead
# of the autouse instant no-op) have a way to sleep without recursing into
# whatever time.sleep currently happens to be patched to.
REAL_SLEEP = _time_module.sleep

os.environ.setdefault('USE_TASK_SCHEDULER', 'true')


@pytest.fixture(scope='session')
def temp_db_path():
    fd, path = tempfile.mkstemp(suffix='.db', prefix='autoremediation_test_')
    os.close(fd)
    yield path
    try:
        os.remove(path)
    except OSError:
        pass


@pytest.fixture(scope='session')
def app_module(temp_db_path):
    """Imports app.py exactly once per test session, against the temp DB."""
    import db_init
    import models

    db_init.DB_PATH = temp_db_path
    models.DB_PATH = temp_db_path

    import app as app_mod  # import-time init_db() runs against temp_db_path here
    return app_mod


@pytest.fixture(scope='session')
def models_module(app_module):
    """Ensures app_module (and its DB patching) has already run first."""
    import models
    return models


@pytest.fixture
def client(app_module):
    app_module.app.config['TESTING'] = True
    with app_module.app.test_client() as c:
        yield c


@pytest.fixture(autouse=True)
def no_real_powershell(monkeypatch):
    """
    Blanket safety net: no test may ever spawn a real PowerShell process.
    Individual tests can still override the mock's .return_value / side_effect
    via the fixture below (mock_subprocess_run) for specific assertions.
    """
    import models as models_mod
    fake = MagicMock()
    fake.return_value = MagicMock(returncode=0, stdout='mocked output', stderr='')
    monkeypatch.setattr(models_mod.subprocess, 'run', fake)
    yield fake


@pytest.fixture(autouse=True)
def instant_sleep(monkeypatch):
    """
    run_remediation() spawns a background verification thread that calls
    time.sleep(verification_timeout_sec). Left real, that's up to 60s of
    dead time per test. Neutered here so the closed-loop worker finishes
    essentially instantly; tests that exercise it poll briefly afterward.
    """
    import models as models_mod
    monkeypatch.setattr(models_mod.time, 'sleep', lambda *_a, **_kw: None)


def wait_until(predicate, timeout=2.0, interval=0.02):
    """Poll a predicate until it's true or timeout elapses (for asserting on
    background-thread side effects without a fixed, flaky sleep)."""
    import time as _time
    deadline = _time.monotonic() + timeout
    while _time.monotonic() < deadline:
        if predicate():
            return True
        _time.sleep(interval)
    return predicate()
