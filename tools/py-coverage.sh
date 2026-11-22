#!/bin/sh
# MCP server tests; fails unless tools/mcp.py is 100% line-covered. Needs `coverage` (pip install coverage; the repo's .venv is used if present).
set -e
cd "$(dirname "$0")/.."
PY=python3; [ -x .venv/bin/python ] && PY=.venv/bin/python
$PY -m coverage run -m unittest discover -s tests
$PY -m coverage report
