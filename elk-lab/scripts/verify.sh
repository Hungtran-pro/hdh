#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Query inside es01 so host port customization does not affect verification.
# Credentials come from the container environment; .env is never sourced as shell code.
docker compose exec -T es01 bash -s <<'REMOTE'
set -euo pipefail
api() {
  curl --fail --silent --show-error --cacert config/certs/ca/ca.crt \
    -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' "$@"
}
echo 'Cluster health:'
api 'https://localhost:9200/_cluster/health?pretty'
echo
echo 'Refresh indices before measuring:'
api -X POST 'https://localhost:9200/lab-logs-*/_refresh?allow_no_indices=false'
echo
echo 'Total, source counts, parse/date failures, success percentage, and timestamp range:'
api 'https://localhost:9200/lab-logs-*/_search?allow_no_indices=false&allow_partial_search_results=false&pretty' -d '{
  "size":0,"track_total_hits":true,
  "aggs":{
    "by_source":{"terms":{"field":"log_type.keyword","size":10},"aggs":{
      "failures":{"filter":{"terms":{"tags.keyword":["_nginx_parse_failure","_apache_parse_failure","_spring_parse_failure","_dateparsefailure","_unknown_source"]}}}
    }},
    "quality":{"filters":{"filters":{"all":{"match_all":{}}}},"aggs":{
      "failed":{"filter":{"terms":{"tags.keyword":["_nginx_parse_failure","_apache_parse_failure","_spring_parse_failure","_dateparsefailure","_unknown_source"]}}},
      "success_percent":{"bucket_script":{"buckets_path":{"failed":"failed>_count","total":"_count"},"script":"params.total > 0 ? 100.0 * (params.total - params.failed) / params.total : 0"}}
    }},
    "earliest":{"min":{"field":"@timestamp"}},"latest":{"max":{"field":"@timestamp"}}
  }
}'
echo
echo 'Sample documents:'
api 'https://localhost:9200/lab-logs-*/_search?allow_partial_search_results=false&pretty' -d '{"size":3,"sort":[{"@timestamp":"asc"}],"_source":["@timestamp","log_type","message","event.original","http","log.level","tags"]}'
echo
REMOTE
# Status endpoint returning HTTP 200 indicates Kibana is available.
docker compose exec -T kibana curl --fail --silent --show-error --cacert config/certs/ca/ca.crt https://localhost:5601/api/status
