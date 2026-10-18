#!/usr/bin/env bash
set -euo pipefail
api() {
  curl --fail-with-body --silent --show-error --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" \
    -H 'kbn-xsrf: elk-lab' -H 'Content-Type: application/json' "$@"
}
BASE=https://kibana:5601
code=$(api -o /dev/null -w '%{http_code}' "$BASE/api/spaces/space/lab" 2>/dev/null || true)
if [[ "$code" == 404 ]]; then
  api -X POST "$BASE/api/spaces/space" -d '{"id":"lab","name":"ELK Lab","description":"Live service and public datasets"}' >/dev/null
elif [[ "$code" != 200 ]]; then echo "Cannot inspect Kibana space (HTTP $code)" >&2; exit 1; fi
for role in analyst viewer; do
  if [[ "$role" == analyst ]]; then access=all; else access=read; fi
  api -X PUT "$BASE/api/security/role/lab_$role" -d "{\"elasticsearch\":{\"cluster\":[],\"indices\":[{\"names\":[\"lab-logs-*\"],\"privileges\":[\"read\",\"view_index_metadata\"]}]},\"kibana\":[{\"base\":[\"$access\"],\"spaces\":[\"lab\"]}]}" >/dev/null
done
# Keep the existing default-space Data View and also prepare the scoped lab space.
for prefix in '' /s/lab; do
  if [[ -z "$prefix" ]]; then view_id=elk-lab; else view_id=elk-live-logs; fi
  code=$(api -o /dev/null -w '%{http_code}' "$BASE$prefix/api/data_views/data_view/$view_id" 2>/dev/null || true)
  if [[ "$code" == 404 ]]; then
    api -X POST "$BASE$prefix/api/data_views/data_view" -d "{\"data_view\":{\"id\":\"$view_id\",\"title\":\"lab-logs-*\",\"name\":\"ELK lab logs\",\"timeFieldName\":\"@timestamp\",\"allowNoIndex\":true}}" >/dev/null
  elif [[ "$code" != 200 ]]; then echo "Cannot inspect Data View (HTTP $code)" >&2; exit 1; fi
  api -X POST "$BASE$prefix/api/data_views/default" -d "{\"data_view_id\":\"$view_id\",\"force\":false}" >/dev/null
done
# Pinned Kibana 8 API; no overwrite: existing student edits are preserved.
code=$(api -o /dev/null -w '%{http_code}' "$BASE/s/lab/api/saved_objects/dashboard/elk-live" 2>/dev/null || true)
if [[ "$code" == 404 ]]; then
  response=$(api -X POST "$BASE/s/lab/api/saved_objects/_bulk_create" --data-binary @/usr/local/share/lab-kibana/live-objects.json)
  if [[ "$response" == *'"error":'* ]]; then
    printf '%s\n' "$response" >&2
    exit 1
  fi
elif [[ "$code" != 200 ]]; then
  echo "Cannot inspect dashboard (HTTP $code)" >&2
  exit 1
fi
printf '\nLab space, scoped roles, Data View and dashboard ready.\n'
