# hdh — Network Operating Systems homework

A single-host ELK Stack lab with real Nginx HTTPS traffic, Filebeat collection, mutual TLS, Logstash parsing and persistent queues, Elasticsearch indexing, and Kibana Discover/dashboard configuration.

The implementation is in [`elk-lab/`](elk-lab/).

- [Installation and operation](elk-lab/README.md)
- [Architecture, security and delivery model](elk-lab/LIVE.md)
- [Presentation walkthrough](elk-lab/DEMO.md)
- [Measured live/security/queue results](elk-lab/reports/LIVE-RESULTS.md)
- [Historical public-dataset analysis](elk-lab/reports/RESULTS.md)

## Start a fresh local deployment

```bash
cd elk-lab
python3 scripts/configure-env.py
docker compose --profile live up -d
```

Docker Engine/Desktop and Compose v2 must be running. See the lab README for Ubuntu prerequisites, local CA trust and login instructions. Each installation generates its own local secrets and certificates; none are provided by this repository. Existing `.env` files and persistent data are preserved.

Measured tests ran on Docker Desktop/macOS ARM64. Ubuntu deployment, browser rendering and multi-host collection remain unverified. Live requests are controlled demonstration traffic generated against a real Nginx service; downloaded historical datasets retain their original attribution.
