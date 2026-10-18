# Live collection, security and reliability

## What makes this a live service

Nginx serves HTTPS on port 8443 and appends each completed request to `runtime/nginx/access.log`. That directory is the application's log location, separate from the downloaded dataset tree. Filebeat reads it through a read-only mount and retains offsets/fingerprints in `filebeatdata`. The optional `traffic` container makes real HTTPS requests every `TRAFFIC_INTERVAL` seconds (default 2); you can also browse the application manually. Nginx, not the client, produces every log line.

Filebeat does not periodically upload the whole file. Once a file is discovered, its harvester tails appended complete lines, batches events and waits for acknowledgements. The scanner interval (1 second) discovers files; the memory-queue flush timeout (1 second) releases partial batches; Logstash parses/buffers them; Elasticsearch refresh makes documents searchable; Kibana refresh (5 seconds on the supplied dashboard) updates the screen. These are separate delays, not one guaranteed delivery interval.

A first live file must reach the configured 128-byte fingerprint threshold. Keep input IDs/fingerprints stable and preserve the registry. Do not delete a file to replay it or use copy/truncate rotation. Rotate by renaming to a unique `access.log.<suffix>` and asking Nginx to reopen its logs (`nginx -s reopen`); Filebeat's `access.log*` pattern covers old/new files. Avoid overwriting an existing rotated file. Rotation itself has not been runtime-tested in this lab.

## Connection and permission model

| Boundary | Encryption | Authentication | Authorization |
|---|---|---|---|
| Client → Nginx | HTTPS, verified server CA/name | Dedicated `demo` Basic-auth credential | App content allowed; `/private/` denied |
| Source file → Filebeat | Local filesystem; no network transport | Container/host filesystem identity | Read-only log mount; registry writable only in its own volume |
| Filebeat → Logstash | TLS 1.2/1.3 with server verification | Mandatory client cert from dedicated Beats-client CA | Only authenticated subject `CN=filebeat` reaches parser/output; other subjects dropped |
| Logstash → ES | HTTPS with CA/hostname verification | `logstash_ingest` | Write/auto-create only `lab-logs-*`, plus monitoring; no user administration |
| Kibana → ES | HTTPS with CA/hostname verification | `kibana_system` | Built-in backend permissions; not used as a human login |
| Human → Kibana | HTTPS | `lab_analyst` or `lab_viewer` | Lab-space editor or reader; both have only read/view-metadata on lab indices |
| ES transport | TLS | CA-signed node certificate | Single-node cluster configuration |
| Logstash monitoring | HTTPS on container loopback | Separate `monitor` password | Read monitoring APIs; endpoint is not published |

The client CA is distinct from the server CA: possession of an Elasticsearch/Kibana/Nginx server certificate does not authorize publishing Beats events. Logstash's Beats protocol does not use an HTTP Basic username/password; it uses mutual TLS instead. The authenticated subject is copied into `tls.client.subject` for evidence.

Human accounts have no index-write, index-delete or security-management privileges. Analyst's `base: all` Kibana permission is limited to the `lab` space; viewer has `base: read`. ES index permissions are independent and stay read-only for both. The lab deliberately uses a broad Kibana editor permission within one space so the group can refine visualizations. Use narrower feature permissions if the assignment requires them.

## Certificate and secret handling

The existing `certs` volume is retained as setup-only signing storage. Elasticsearch now mounts `es_certs`, containing only its own identity and public CA, rather than the signing storage. Other services mount separate `*_certs` volumes. Only setup has signing keys; Logstash cannot read Filebeat's private key and Filebeat cannot read Logstash/ES keys.

Certificates are reused rather than silently replaced. Logstash gets an unencrypted PKCS#8 PEM key for Beats and a password-protected PKCS#12 keystore for its monitoring API. Private identity volumes use restrictive ownership; Elastic service identities are readable by UID 1000. Nginx's password file is readable by its worker group 101. Public CA material is separate and shareable.

`python3 scripts/configure-env.py` creates a fresh `.env` once, with random secrets and mode 600. Existing `.env` files are preserved. Bootstrap creates missing analyst/viewer accounts without resetting existing passwords. Backend service credentials are reapplied from the existing configured values. Changing `.env` alone is not a rotation procedure: coordinate existing account/htpasswd/encryption-key changes explicitly. Never publish `.env`, private keys or expanded Compose output.

Issued live-service/client certificates last 365 days. Monitor expiry and plan renewal; there is no automatic CA rotation or renewal controller. Keep the same Kibana encryption key so sessions and encrypted saved objects remain usable.

These controls protect network traffic and service access. They do not encrypt host disks, prevent a Docker administrator from accessing container secrets, or make this single-machine lab highly available. Use host full-disk encryption/backups if required by the course. Host ports bind to loopback; only explicitly configured SSH tunnels should bridge remote demonstration access.

## Persistent queue and delivery semantics

Logstash writes accepted Beats events to a persisted queue under `logstashdata`. Filters and the Elasticsearch output process them; acknowledgements release queue entries after delivery. With Elasticsearch temporarily unavailable, output retries and the queue accumulates events. When the queue fills, backpressure propagates to Filebeat; Filebeat's local source files and registry support retry. Do not remove source logs while delivery is incomplete.

`queue.checkpoint.writes: 1` prioritizes durable writes over throughput; its default maximum capacity is 1 GiB. `logstashdata` survives container recreation. Filebeat's configured local buffer is in memory, so source files/registry are still necessary. The pipeline is **at least once**: crashes/retries can duplicate events. A mapping rejection can go to the DLQ rather than appear as a Grok failure; inspect both.

Run the opt-in demonstration only when the lab can tolerate a brief interruption:

```bash
python3 scripts/demo-queue.py
```

It stops only lab ES, observes 20 seconds of queue growth, restores ES in `finally`, waits for green health, pauses the optional request client, compares source lines to indexed live documents, checks that the queue drains, then resumes the client. It does not delete data. A configured persistent queue and an outage recovery test do not establish power-loss durability or exactly-once delivery.

## Moving the source to another machine

The normal architecture places Filebeat **on the source host**, beside the service writing the logs. It forwards events over TLS to a central Logstash endpoint; the central server does not tail a remote path merely because its filename appears in YAML.

This repository demonstrates that boundary with separate Nginx/Filebeat containers and independent mounts on one machine. For a multi-host extension, deploy Filebeat on the source host, point its input at the actual local application log directory, provision its own client identity, issue a Logstash server certificate covering the chosen DNS name, publish/firewall 5044 only for source hosts, and update Filebeat's output host. Extend the subject allowlist for each approved shipper. Do not use the current `localhost` certificates against arbitrary IPs or expose Beats without mutual TLS. Multi-host deployment is not part of the executed test.

## Primary references

- [Filebeat → Logstash mutual TLS](https://www.elastic.co/docs/reference/beats/filebeat/configuring-ssl-logstash)
- [Beats input TLS settings and peer metadata](https://www.elastic.co/guide/en/logstash/8.19/plugins-inputs-beats.html)
- [Logstash monitoring API TLS/authentication](https://www.elastic.co/guide/en/logstash/8.19/monitoring-logstash.html)
- [Kibana HTTPS configuration](https://www.elastic.co/guide/en/kibana/8.19/settings.html)
- [Kibana space-scoped role API](https://www.elastic.co/docs/api/doc/kibana/v8/operation/operation-put-security-role-name)

Dashboard definitions use the pinned Kibana 8 Saved Objects API. Bootstrap preserves an existing dashboard rather than overwriting group members' edits. Export edited dashboards through Kibana for handover; the supplied JSON is a starting configuration and has not passed visual browser inspection here.
