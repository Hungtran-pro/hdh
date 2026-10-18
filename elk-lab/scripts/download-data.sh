#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/nginx data/apache data/spring
# Preserve existing inputs and their registry identity. Do not truncate live files.
if [[ -e data/nginx/access.log || -e data/apache/error.log ]]; then
  echo 'Inputs already exist. Leave them in place; use a separate lab directory for a new dataset.' >&2
  exit 1
fi
work=$(mktemp -d data/.download.XXXXXX)
trap 'rm -rf "$work"' EXIT
NGINX_URL='https://raw.githubusercontent.com/elastic/examples/master/Common%20Data%20Formats/nginx_logs/nginx_logs'
APACHE_URL='https://zenodo.org/records/8196385/files/Apache.tar.gz?download=1'
curl -fL --retry 3 --connect-timeout 20 "$NGINX_URL" -o "$work/access.log"
curl -fL --retry 3 --connect-timeout 20 "$APACHE_URL" -o "$work/Apache.tar.gz"
python3 scripts/extract_apache.py "$work/Apache.tar.gz" "$work/error.log"
test -s "$work/access.log"
test -s "$work/error.log"
mv "$work/access.log" data/nginx/access.log
mv "$work/error.log" data/apache/error.log
printf 'Nginx: %s\nApache: %s\nRetrieved UTC: %s\n' "$NGINX_URL" "$APACHE_URL" "$(date -u +%FT%TZ)" > data/SOURCES.txt
python3 - <<'PY'
import hashlib
from pathlib import Path
files = [Path('data/nginx/access.log'), Path('data/apache/error.log')]
with Path('data/SHA256SUMS').open('w') as manifest:
    for path in files:
        content = path.read_bytes()
        original_hash = hashlib.sha256(content).hexdigest()
        with Path('data/SOURCES.txt').open('a') as provenance:
            provenance.write(f'{path}: downloaded SHA256 {original_hash}\n')
        if not content.endswith(b'\n'):
            # Filebeat waits for a newline before publishing the final record.
            content += b'\n'
            path.write_bytes(content)
            with Path('data/SOURCES.txt').open('a') as provenance:
                provenance.write(f'{path}: appended missing final newline; log text unchanged\n')
        manifest.write(f'{hashlib.sha256(content).hexdigest()}  {path}\n')
        print(f'{path}: {len(content.splitlines())} lines')
PY
