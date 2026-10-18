#!/usr/bin/env bash
set -euo pipefail
CA=/usr/share/elasticsearch/config/certs/ca/ca.crt
URL=https://es01:9200
api() { curl --fail --silent --show-error --cacert "$CA" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' "$@"; }
# These values enter JSON below; enforce the documented lab password contract.
for name in KIBANA_PASSWORD LOGSTASH_PASSWORD LAB_ANALYST_PASSWORD LAB_VIEWER_PASSWORD; do
  value=${!name}
  if [[ ! "$value" =~ ^[A-Za-z0-9]{20,}$ || "$value" == ChangeThis* ]]; then
    echo "$name must be replaced with at least 20 alphanumeric characters" >&2
    exit 1
  fi
done
api -X PUT "$URL/_index_template/lab-logs" --data-binary @/usr/local/share/lab-template.json >/dev/null
echo 'Setting kibana_system password...'
api -X POST "$URL/_security/user/kibana_system/_password" -d "{\"password\":\"${KIBANA_PASSWORD}\"}" > /dev/null
# Custom lab writer role. Lab passwords in .env must be alphanumeric to avoid JSON escaping.
echo 'Configuring least-privilege Logstash ingest user...'
api -X PUT "$URL/_security/role/logstash_ingest" -d '{"cluster":["monitor"],"indices":[{"names":["lab-logs-*"],"privileges":["auto_configure","create_index","create","write","view_index_metadata"]}]}' > /dev/null
api -X PUT "$URL/_security/user/logstash_ingest" -d "{\"password\":\"${LOGSTASH_PASSWORD}\",\"roles\":[\"logstash_ingest\"]}" > /dev/null
echo 'Built-in Kibana user and Logstash ingest user configured.'

# Add human accounts without resetting any existing account's password.
for name in lab_analyst lab_viewer; do
  code=$(api -o /dev/null -w '%{http_code}' "$URL/_security/user/$name" 2>/dev/null || true)
  if [[ "$code" == 404 ]]; then
    if [[ "$name" == lab_analyst ]]; then password=$LAB_ANALYST_PASSWORD; else password=$LAB_VIEWER_PASSWORD; fi
    api -X POST "$URL/_security/user/$name" -d "{\"password\":\"$password\",\"roles\":[\"$name\"]}" >/dev/null
    echo "Created $name; space-scoped role is installed by setup-kibana.sh."
  elif [[ "$code" != 200 ]]; then
    echo "Cannot inspect $name (HTTP $code); no password changed" >&2
    exit 1
  fi
done
