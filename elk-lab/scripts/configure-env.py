#!/usr/bin/env python3
"""Create fresh local secrets once; never overwrite an existing .env."""
import os
from pathlib import Path
import secrets

root = Path(__file__).resolve().parent.parent
target = root / '.env'
if target.exists():
    print('.env already exists; existing passwords and settings preserved.')
else:
    lines = []
    for line in (root / '.env.example').read_text().splitlines():
        key, sep, value = line.partition('=')
        if sep and (key.endswith('PASSWORD') or key == 'KIBANA_ENCRYPTION_KEY'):
            line = key + '=Ls9' + secrets.token_hex(24)
        lines.append(line)
    with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
        stream.write('\n'.join(lines) + '\n')
    print('Created .env with unique local secrets and mode 600; no credentials printed.')
