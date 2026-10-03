#!/bin/sh
# Hermes launcher wrapper — activated at runtime.
# Finds the venv Python and sets up the correct import paths.
set -e

# Locate the venv Python (has all dependencies installed)
VENV_PY="$(find /opt/hermes-agent/.hermes/installs -name python3 -path '*/venv/bin/*' 2>/dev/null | head -1)"

# Fallback: use the hermetic tools Python
if [ -z "$VENV_PY" ]; then
    VENV_PY="$(find /opt/hermes-agent/.hermes/tools -name python3 -path '*/bin/*' 2>/dev/null | head -1)"
fi

if [ -z "$VENV_PY" ]; then
    echo "FATAL: no Hermes Python interpreter found" >&2
    exit 1
fi

# Run Hermes with the venv site-packages available
exec "$VENV_PY" -I -c "
import os, re, sys

os.environ.pop('PYTHONHOME', None)
os.environ.pop('PYTHONPATH', None)

# Add the Hermes source directory
sys.path.insert(0, '/opt/hermes-agent')

# Add all venv site-packages (dependencies live here)
import glob
for sp in glob.glob('/opt/hermes-agent/.hermes/installs/*/environments/*/venv/lib/python*/site-packages'):
    if sp not in sys.path:
        sys.path.insert(0, sp)
for sp in glob.glob('/opt/hermes-agent/.hermes/installs/*/pm-runtime/generations/*/lib/python*/site-packages'):
    if sp not in sys.path:
        sys.path.insert(0, sp)

from hermes_cli.main import main
sys.argv[0] = re.sub(r'(-script\.pyw|\.exe)?$', '', sys.argv[0])
sys.exit(main())
" "$@"