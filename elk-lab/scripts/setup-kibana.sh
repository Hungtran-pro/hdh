#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Reapply roles and create missing objects; preserve existing dashboards and passwords.
docker compose run --rm --no-deps kibana-setup
