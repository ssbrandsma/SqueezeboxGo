"""Shared helpers for host-runnable QA checks (Agent 6).

Conventions:
  * Statuses: PASS, FAIL, NOT RUN (no targets / nothing to do yet),
    BLOCKED (a required tool or input is missing).
  * Exit codes: PASS=0, FAIL=1, ERROR=2, NOT RUN=3, BLOCKED=4.
  * Every check supports --json (single JSON object on stdout) and
    --root DIR (repo root autodetected via git when omitted).
"""

import json
import os
import subprocess
import sys

PASS = "PASS"
FAIL = "FAIL"
NOTRUN = "NOT RUN"
BLOCKED = "BLOCKED"

EXIT = {PASS: 0, FAIL: 1, NOTRUN: 3, BLOCKED: 4}


def repo_root(start=None):
    """Return the repo top level (git) or fall back to start/cwd."""
    start = start or os.getcwd()
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=start, capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()
    except Exception:
        pass
    d = os.path.abspath(start)
    while True:
        if os.path.exists(os.path.join(d, "AGENTS.md")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.path.abspath(start)
        d = parent


def emit(check, status, details, target=None, json_mode=False):
    """Print a check result; return the process exit code."""
    if isinstance(details, str):
        details = [details]
    if json_mode:
        print(json.dumps({
            "check": check,
            "status": status,
            "target": target or "",
            "details": details,
        }))
    else:
        for line in details:
            print(f"[{check}] {line}")
        print(f"[RESULT] {check}: {status}")
    return EXIT[status]


def which(tool):
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = os.path.join(d, tool)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)
