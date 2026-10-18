# Repository review and validation

## Phase 1 — original repository (read-only inspection)

Inspected all files before edits. No AGENTS.md was found. The workspace contains the extracted `elk-lab` and `code.zip`; it is not a Git checkout. All four runtime images and both bootstrap images use the same `.env.example` pin, **8.19.23**. No incompatible version or definite YAML syntax error was found.

| Original file | Purpose | Dependencies | Issues identified |
|---|---|---|---|
| `docker-compose.yml` | Six services, startup graph, ports, volumes, limits | `.env`, Docker Compose, scripts | All clients shared private-key volume; memory-only Logstash queue; fixed Kibana encryption key |
| `.env.example` | Versions, credentials, ports, limits | Compose | Placeholder credentials accepted; no encryption-key setting |
| `.gitignore` | Secret/generated file exclusions | Git | Downloaded logs not excluded |
| `README.md` | Basic deployment and diagnostics | All components | Missing diagram, detailed operations, troubleshooting and validation account |
| `filebeat/filebeat.yml` | Three filestream inputs, Beats output | `/logs`, Logstash, registry | No Spring multiline; source files absent initially |
| `logstash/pipeline/logstash.conf` | Beats input, Grok/date filters, ES output | Credentials and CA | No explicit mapping/template; no explicit original-event field; optional Spring format untested |
| `scripts/setup.sh` | CA and node cert generation | certutil, unzip, writable volume | Private CA/node keys shared with every certificate client |
| `scripts/init-users.sh` | System-user password and writer role | Healthy authenticated ES | JSON interpolation required unenforced password restrictions; no template bootstrap |
| `scripts/download-data.sh` | Public downloads and hashes | curl, Python, upstream URLs | Truncates existing inputs; global fixed `/tmp` archive; no final-newline handling |
| `scripts/extract_apache.py` | Archive member selection/copy | tarfile | Largest matching file could be unrelated; no exact Apache filename requirement |
| `scripts/verify.sh` | Health/count queries | Docker, curl, credentials | Sources `.env` as code; assumes host port 9200; no exact total/success rate/date-failure metric |
| `data/*/.gitkeep` | Empty source directories | Downloader | No real data present at initial inspection |

Original startup graph: setup completes → ES becomes healthy → init-users completes → Kibana and Logstash start → Filebeat starts when Logstash's Beats port listens. One-shot containers are intentionally allowed to exit. Service DNS uses the default Compose network. Ports 9200 and 5601 bind to loopback via environment settings; Beats and Logstash monitoring ports are unpublished. ES has authenticated TLS HTTP and transport; Filebeat→Logstash is plain TCP. ES, Kibana and Filebeat state were already persistent. JVM/container limits were reasonable starting points, not measured capacity guarantees.

## Phases 2–3 — prioritized fixes

| Priority | Confirmed issue | Implemented fix |
|---|---|---|
| High | Clients could read CA and ES private keys | New `public_certs` volume contains only CA certificate; private volume limited to setup and ES |
| High | Downloader could overwrite live source files | Refuse existing inputs; stage downloads using unique temporary directory |
| High | Fixed Kibana encryption key and accepted default credentials | Environment encryption key; bootstrap validates replacement alphanumeric passwords |
| Medium | Dynamic mapping and replica defaults left lab behavior implicit | New bootstrap index template: explicit core fields, one shard, zero replicas; daily indices explicitly selected |
| Medium | Logstash in-flight state lost on recreation | Persistent queue and DLQ on `logstashdata`; checkpoint every write; duplicates still possible |
| Medium | Verification omitted failures and exact totals | Exact hit count, per-source counts/failures, date failures, success percentage, range, samples and Kibana status |
| Medium | Verification executed `.env` and fixed a host port | Execute authenticated query inside ES with existing container environment |
| Medium | Archive selection could pick unrelated logs | Require exactly one full regular `Apache.log`; copy bytes without unpacking archive paths |
| Medium | Downloaded Apache final record had no newline | Record original hash and append final newline before checksumming; no log text fabricated |
| Low | Optional Spring stack traces split across events | Filebeat multiline and multiline-aware Grok; include ISO date handling and explicit Vietnam fallback timezone |
| Low | Original message not explicitly retained as an ECS field | Copy `message` to `event.original`; preserve message as well |
| Low | Incomplete handover guidance | Expanded README with diagram, operation, ownership, security and troubleshooting |

No persistent volumes, credentials in an existing deployment or user data were reset. No Docker cleanup was performed. ILM and data streams remain disabled; no retention policy deletes historical logs. Mappings are a baseline for Huynh to extend. The writer has `monitor` on the cluster and scoped index auto-configuration/create/write permissions, not template administration.

## Phase 4 — initial observed validation (superseded by runtime follow-up)

Local environment: macOS ARM64, Docker CLI 28.4.0, standalone Docker Compose **v2.39.4-desktop.1**, Python 3.14. Target remains Ubuntu. The `docker compose` plugin invocation is unavailable in this environment; standalone Compose works.

| Check | Observed outcome |
|---|---|
| `docker-compose --env-file .env.example config --quiet` | Passed after final changes |
| `bash -n scripts/setup.sh scripts/init-users.sh scripts/download-data.sh scripts/verify.sh` | Passed |
| Python extractor AST parse | Passed |
| Index-template JSON parse | Passed |
| Public dataset download | Passed with approved network access after sandbox DNS failed |
| Nginx input records | 51,462, counted from downloaded bytes |
| Apache input records | 56,482, counted from downloaded bytes; differs from upstream summary, so retain measured count |
| Input SHA256 checks and newline checks | Passed against generated manifest |
| Repeated downloader execution | Correctly refused existing files (exit 1); files preserved |
| `docker version` server access | Failed: Docker daemon unavailable |
| Compose `ps` and `logs --tail=100` | Failed: Docker daemon unavailable |
| Filebeat native config/output checks | Not executed: daemon unavailable |
| Logstash native config test and actual Grok/date evaluation | Not executed: daemon unavailable |
| ES ingestion, exact indexed counts, parsing success, Kibana UI | Not executed; no runtime metrics claimed |

File counts alone do not establish successful parsing or ingestion. Dataset hashes and URLs are in `data/SHA256SUMS` and `data/SOURCES.txt`. These manifests and logs are local generated artifacts and are ignored by Git.

## Phase 5 — handover and outstanding runtime work

README documents prerequisites, environment values, download, service order, volumes, Filebeat state, security, verification, historical Discover queries, shutdown/restart and troubleshooting. Start the Docker engine on the Ubuntu host, configure real `.env` values, and run the documented checks. Capture `verify.sh` output only after ingestion stabilizes and inspect pipeline errors/DLQ before reporting results. Actual Spring Boot compatibility requires authentic application samples. Those were the initial review limits. The subsequent Docker Desktop runtime follow-up is recorded in [reports/RESULTS.md](reports/RESULTS.md).

## Primary references consulted

- [Elastic Stack 8.19.23 release](https://www.elastic.co/blog/elastic-stack-8-19-23-released)
- [Logstash 8.19 Elasticsearch output](https://www.elastic.co/guide/en/logstash/8.19/plugins-outputs-elasticsearch.html)
- [Elastic ECS defaults in Logstash](https://www.elastic.co/docs/reference/logstash/ecs-ls)
- [Elastic Nginx examples](https://github.com/elastic/examples/tree/master/Common%20Data%20Formats/nginx_logs)
- [Loghub dataset listing and provenance](https://github.com/logpai/loghub/blob/master/README.md)

## Runtime follow-up

Docker Desktop became available. Preserved the existing Elasticsearch administrator password and all volumes, generated missing service secrets in the gitignored local `.env`, and restricted its file permissions. Bootstrap now validates only service passwords embedded in JSON; administrator authentication accepts the existing credential unchanged. Added `scripts/setup-kibana.sh` for repeatable Data View creation and disabled partial search responses in verification so missing shards cannot silently produce incomplete metrics. Native configuration checks and API-level end-to-end validation were executed; see [runtime results](reports/RESULTS.md). Browser discovery found no available browser, so UI rendering remains unverified.

## Live-service extension

The next authorized task replaced the plaintext collection/browser links with mutual TLS Beats and HTTPS Kibana, added a real HTTPS Nginx service plus an optional actual request client, separated signing/identity volumes, added scoped analyst/viewer roles and a lab dashboard, and secured Logstash monitoring. Existing historical records, registry and administrator password were preserved. Logstash image UID/group differences required explicit identity ownership; its legacy image settings required a mounted `logstash/logstash.yml`. Scoped Data Views need distinct IDs because Kibana 8 IDs are globally unique across spaces. The queue-demo Count API request uses supported parameters and checks shard failures explicitly. See [LIVE.md](LIVE.md) and [live measured results](reports/LIVE-RESULTS.md); earlier plaintext descriptions describe the original implementation only.
