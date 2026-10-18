# Live demonstration for the lecturer

The demo is a real HTTPS service: the client sends requests; Nginx writes access logs; Filebeat tails them; Logstash authenticates/parses/buffers; Elasticsearch indexes; Kibana queries and refreshes.

## Start from the existing lab

From `elk-lab/`:

```bash
docker compose --profile live up -d
docker compose ps -a
```

Preserve `.env`, all volumes and source files. To set up a fresh copy, run `python3 scripts/configure-env.py` before Compose. The existing workspace is already configured.

## Show continuous collection

1. Trust the exported `.local/ca.crt` in the browser used for the lab (see README). Never share a private key.
2. Open **https://localhost:8443**, log in as `demo` with `WEB_PASSWORD` from `.env`. Refresh the page and open `/missing` or `/private/` to generate actual 200/404/403 responses.
3. In a terminal run `tail -f runtime/nginx/access.log`. Explain that the source is the running application's file, separate from `data/`.
4. Open **https://localhost:5601/s/lab**, sign in as `lab_analyst` with `LAB_ANALYST_PASSWORD` from `.env`.
5. Open **Dashboard → ELK Live Service**. Use **Last 15 minutes**, refresh **5 seconds**. It has live request count, HTTP status distribution, timeline and event table.
6. In **Discover**, select **ELK lab logs**, use `log_origin: "live"`, Last 15 minutes, and enable refresh. Expand a document and show `message`, `event.original`, `@timestamp`, HTTP fields and `tls.client.subject: CN=filebeat`.
7. Explain that Filebeat tails new complete lines; its scanner, batch timeout, ES refresh and dashboard refresh are different mechanisms. Timing is near real time, not a strict fixed interval.

The optional `traffic` client sends one real HTTPS request every 2 seconds by default. To pause/resume that client alone:

```bash
docker compose stop traffic
docker compose up -d --no-deps traffic
```

The website stays available for manual requests. Requests are controlled demo traffic; their logs are genuinely produced by Nginx and are not described as public historical datasets.

## Show security

Sign in as `lab_viewer` with `LAB_VIEWER_PASSWORD`: it can view the lab but cannot edit dashboards. Analyst can edit lab-space objects but cannot write/delete Elasticsearch indices or administer users. Service accounts are separate from human accounts.

```bash
python3 scripts/check-live.py
```

This runs real positive and negative checks: unauthenticated endpoints rejected; mandatory Beats client certificate; writer limited to lab indices; human users read-only in ES and scoped to lab space; viewer/analyst dashboard permissions; real request indexed with its verified Filebeat TLS identity. Measured evidence is saved in `reports/live-security.json`.

## Show buffering and recovery

Tell the group that Elasticsearch will be unavailable briefly, then run:

```bash
python3 scripts/demo-queue.py
```

Nginx and Filebeat continue while ES is stopped. Show persisted queue growth, automatic ES restoration and queue drain. The script briefly pauses the optional client to compare stable physical source-line and indexed-live-record counts, then resumes it. See `reports/queue-recovery.json`. This is an outage demo, not a crash/power-loss test.

## Optional historical-data analysis

Use `log_type: "nginx"` and May–June 2015 for the public Nginx sample; use `log_type: "apache_error"` and 2005–2006 for Apache. The old public records may lack `log_origin`. The original 107,944-document analysis is in `reports/RESULTS.md`. Its 4,478 bare Apache messages lack timestamps and are correctly flagged; do not confuse their ingestion dates with live service traffic.

## Stop without deleting data

```bash
docker compose stop
docker compose start
```

No `down -v`, pruning, registry deletion or dataset overwrite. Runtime services restart unless explicitly stopped; Docker Engine/Desktop must itself be running. Live files/indices grow over time; pause the optional client after presentations if desired.
