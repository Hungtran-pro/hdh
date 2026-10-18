# Live service and security results

Executed on Docker Desktop/macOS ARM64 with Elastic 8.19.23. These are actual observations, separate from the historical public-dataset run. The live client remains running, so current counts continue increasing.

## Live request-to-search test

- All **24 checks passed** at 2026-10-18T10:08:26.775020+00:00.
- A unique authenticated HTTPS request to Nginx generated a real access-log record and became searchable after **2.073 seconds** in this observation. This is not a guaranteed latency or benchmark.
- Live indexed records increased from **145 to 150** during the test.
- The indexed document contained parsed HTTP status 404, original message, `log_origin: live`, authenticated `tls.client.subject: CN=filebeat` and TLS 1.3 metadata.
- Filebeat native configuration/output tests passed; its output test negotiated TLS 1.3 with certificate-chain verification.
- Final TLS-enabled Logstash native configuration test returned `Configuration OK` and exited 0.

## Security checks executed

- Unauthenticated Elasticsearch, Kibana data access and Nginx requests returned 401.
- Authenticated Nginx access returned 200; private-path access returned 403.
- Viewer and analyst could read lab indices and the lab dashboard; neither could access the default-space Data View.
- Both human users had read access but no index-write/index-delete or security-management privileges.
- Viewer had dashboard-read permission and lacked dashboard-edit permission; analyst had dashboard-edit permission in the lab space.
- Logstash writer could write lab indices but could not write unrelated indices or manage security.
- A Beats client without a client certificate was rejected by TLS.
- Logstash monitoring without credentials returned 401 over verified HTTPS.
- Searches completed without partial-shard failures and cluster health was green.

Kibana's list-Data-Views endpoint returns an empty list for inaccessible views; the negative test uses direct saved-object access, which correctly returns 403. Server TLS and RBAC were verified through APIs, not by visual inspection.

## Persistent queue outage and recovery

At 2026-10-18T10:14:30.849741+00:00:

| Observation | Measured value |
|---|---:|
| Queue before interruption | 0 events |
| Queue after 20-second ES outage hold | 7 events |
| Queue after recovery | 0 events |
| Actual live source lines while client paused | 266 |
| Indexed live documents at reconciliation | 266 |

Elasticsearch returned green after recovery. Nginx/Filebeat kept running during the interruption. The optional client was paused only for stable count reconciliation, then resumed. No volumes, indices, source files or registry entries were deleted. The test demonstrates outage buffering and recovery; abrupt crash/power-loss durability and exactly-once delivery were not tested.

## Final API snapshot

The final full verification observed **108,271 total documents**, including historical records and accumulating live records; this number will change. The original historical dataset results remain in [RESULTS.md](RESULTS.md).

- [live-security.json](live-security.json): individual check results and the real probe document.
- [queue-recovery.json](queue-recovery.json): actual interruption/reconciliation measurements.
- [live-verification.txt](live-verification.txt): final cluster/count/sample/Kibana output.
- [live-services.txt](live-services.txt): final Compose status.
- [live-dashboard.ndjson](live-dashboard.ndjson): actual Kibana export including dashboard dependencies and Data View, suitable for review/import with conflict handling.

## Remaining limits

Browser rendering was not verified because no browser was connected. The dashboard was created, fetched under scoped human credentials and exported successfully; its visual appearance still needs inspection on the presentation machine. Ubuntu, multi-host shipping, source rotation and real Spring Boot formats remain untested. No administrator password was reset; local `.env` keeps existing credentials and generated new service/human secrets. Host-disk encryption, automatic renewal and high availability are not implemented.
