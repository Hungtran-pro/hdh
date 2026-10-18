#!/usr/bin/env python3
"""Opt-in lab outage demo: stop ES briefly, observe PQ, restore, reconcile logs.

No volumes, indices, source files or Filebeat registry entries are deleted.
"""
from datetime import datetime, timezone
import json
from pathlib import Path
import runpy
import time
import urllib.error

helpers = runpy.run_path(str(Path(__file__).with_name('check-live.py')))
ROOT, compose, config, client, request = [helpers[n] for n in ('ROOT', 'compose', 'config', 'client', 'request')]


def queue():
    command = 'curl --fail --silent --show-error --cacert config/certs/ca/ca.crt -u "monitor:${LOGSTASH_API_PASSWORD}" https://localhost:9600/_node/stats/pipelines/main'
    return json.loads(compose('exec', '-T', 'logstash', 'bash', '-c', command))['pipelines']['main']


def main():
    if 'traffic' not in compose('--profile', 'live', 'ps', '--status', 'running', '--services').splitlines():
        raise SystemExit('Start the live profile first; this demo requires its request generator.')
    env, context = config(), client()
    es = 'https://localhost:' + env['ES_PORT'].rsplit(':', 1)[-1]
    before = queue()['queue']['events_count']
    print('Stopping Elasticsearch for 20 seconds; Nginx and Filebeat continue running.', flush=True)
    # Always restore ES, including on a failed observation or Ctrl+C.
    try:
        compose('stop', 'es01')
        time.sleep(20)
        offline = queue()['queue']['events_count']
        print(f'Persisted queued events: {before} -> {offline}', flush=True)
        if offline <= before:
            raise RuntimeError('Persistent queue did not grow during the outage')
    finally:
        compose('up', '-d', '--no-deps', 'es01')
        print('Elasticsearch restarted; waiting for recovery.', flush=True)
    deadline = time.monotonic() + 120
    while True:
        try:
            status, health = request(es + '/_cluster/health', context, 'elastic', env['ELASTIC_PASSWORD'])
            ready = status == 200 and health['status'] == 'green'
        except (urllib.error.URLError, OSError):
            ready = False
        if ready:
            break
        if time.monotonic() >= deadline:
            raise RuntimeError('ES was restarted but health did not recover within 120 seconds')
        time.sleep(2)
    # Pause only the optional client to compare stable file and index totals.
    deadline = time.monotonic() + 120
    paused = False
    try:
        compose('stop', 'traffic')
        paused = True
        source_count = len((ROOT / 'runtime/nginx/access.log').read_bytes().splitlines())
        while True:
            status, data = request(es + '/lab-logs-*/_count?allow_no_indices=false', context,
                                   'elastic', env['ELASTIC_PASSWORD'], {'query': {'term': {'log_origin.keyword': 'live'}}})
            stats = queue()
            if status == 200 and data['_shards']['failed'] == 0 and data['count'] == source_count and stats['queue']['events_count'] == 0:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError('Queue/count reconciliation did not complete within the recovery window')
            time.sleep(2)
        report = {'observed_at': datetime.now(timezone.utc).isoformat(),
                  'outage_hold_seconds': 20, 'queue_before': before, 'queue_during_outage': offline,
                  'queue_after_recovery': stats['queue']['events_count'],
                  'live_source_lines': source_count, 'live_indexed_documents': data['count'],
                  'cluster_status': health['status'], 'logstash_output': stats['plugins']['outputs'][0].get('documents'),
                  'dead_letter_queue': stats['dead_letter_queue'],
                  'crash_recovery_tested': False}
        (ROOT / 'reports/queue-recovery.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f'Recovered: queue empty; {source_count} source lines = {data["count"]} indexed live records.', flush=True)
    finally:
        if paused:
            compose('up', '-d', '--no-deps', 'traffic')
            print('Live request generator resumed.', flush=True)


if __name__ == '__main__':
    main()
