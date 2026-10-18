# Measured lab results — 18 October 2026

The full public-dataset → Filebeat → Logstash → authenticated HTTPS Elasticsearch pipeline was executed on **Docker Desktop on macOS ARM64**, using Elastic 8.19.23. Kibana was verified through its API. Ubuntu deployment and browser rendering remain untested.

## Ingestion and parsing

| Source | Indexed records | Parsed records | Parse failures | Parse success |
|---|---:|---:|---:|---:|
| apache_error | 56,482 | 52,004 | 4,478 | 92.0718% |
| nginx | 51,462 | 51,462 | 0 | 100.0000% |
| **Total** | **107,944** | **103,466** | **4,478** | **95.8516%** |

Both per-source indexed counts match the corresponding input file line counts. Elasticsearch returned exact total hits, no search timeout and zero failed shards. Logstash reported 107,944 successful document writes and zero queued events. DLQ reported no errors or dropped/expired events (its one-byte empty-storage overhead is not a failed event).

The source Apache file contains exactly **4,478 standalone lines** reading `script not found or unable to stat`, without timestamp or severity. All 4,478 are retained and tagged `_apache_parse_failure`. Their timestamps are ingestion times. No `_dateparsefailure`, Nginx parse failure, Spring parse failure or unknown-source tags appeared in the final aggregation. Do not label these unstructured source lines as successful timestamp parses or invent missing fields.

## Actual dataset observations

Nginx HTTP status distribution:

| HTTP status | Records |
|---|---:|
| 404 | 33,876 |
| 304 | 13,330 |
| 200 | 4,028 |
| 206 | 186 |
| 403 | 38 |
| 416 | 4 |

Apache severity for records with a parsed header:

| Level | Records |
|---|---:|
| error | 38,081 |
| notice | 13,755 |
| warn | 168 |

These observations describe these particular public historical datasets, not the university network or a current production server. A 404 count is not evidence of an attack without additional analysis.

## Checks executed

- Compose configuration validation passed.
- Certificate and user bootstrap exited successfully.
- Elasticsearch, Kibana and Logstash healthchecks passed; Filebeat remained running.
- Filebeat native `test config` returned `Config OK`.
- Filebeat `test output` resolved and connected to Logstash; plaintext Beats warning matches the private-bridge lab design.
- Logstash native `--config.test_and_exit` returned `Configuration OK` and exited 0.
- Authenticated Elasticsearch health query returned `green`.
- Final verification returned all 107,944 records, original-message samples and parsing metrics.
- Kibana `/api/status` returned overall `available`.
- Created and fetched Data View `elk-lab`, title `lab-logs-*`, timestamp `@timestamp`.
- No browser was available for a visual Discover check; no visual UI success is claimed.
- Spring Boot input has no authentic dataset yet and was not tested with application events.

## Evidence files

- [verification.txt](verification.txt): cluster health, exact counts, metrics, samples and Kibana status.
- [services.txt](services.txt): final container state.
- [logstash-stats.json](logstash-stats.json): actual queue, filters, output delivery and DLQ statistics.
- [analysis.json](analysis.json): source, severity, status and failure-tag aggregations.
- [kibana-data-view.json](kibana-data-view.json): actual Data View API response.
- `../data/SOURCES.txt` and `../data/SHA256SUMS`: local dataset provenance and hashes.

The existing Elasticsearch administrator password was preserved. Missing service secrets were generated in the local gitignored `.env`; no real credentials are included in these reports. Named volumes and file-reading state were preserved. Counts matching inputs do not prove exactly-once delivery under every failure scenario.

## Subsequent live extension

The measurements above are the preserved historical-dataset run. The lab now also collects real current Nginx service events through mutual TLS, serves Kibana over HTTPS and uses scoped human roles. Live totals continue increasing and should be filtered with `log_origin: live`. See [LIVE-RESULTS.md](LIVE-RESULTS.md) for separate live/outage/security evidence.
