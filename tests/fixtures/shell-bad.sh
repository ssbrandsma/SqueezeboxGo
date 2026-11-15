#!/usr/bin/env bash
# Fixture: broken script (unclosed if).
set -euo pipefail
if [ -n "x" ]; then
  echo "never closed"
