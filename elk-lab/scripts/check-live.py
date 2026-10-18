#!/usr/bin/env python3
"""Verify the running live lab without printing credentials or modifying data."""
import base64
from datetime import datetime, timezone
import json
import pathlib
import ssl
import subprocess
import time
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent


def compose(*args, **kwargs):
    return subprocess.run(['docker', 'compose', *args], cwd=ROOT, check=True,
                          capture_output=True, text=True, **kwargs).stdout


def config():
    # Deliberately supports the simple KEY=value format documented by this lab.
    return {k.strip(): v.strip().strip('"').strip("'")
            for line in (ROOT / '.env').read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('#') and '=' in line
            for k, v in [line.split('=', 1)]}


def client():
    local = ROOT / '.local'
    local.mkdir(mode=0o700, exist_ok=True)
    compose('cp', 'es01:/usr/share/elasticsearch/config/certs/ca/ca.crt', str(local / 'ca.crt'))
    return ssl.create_default_context(cafile=str(local / 'ca.crt'))


def request(url, context, user=None, password=None, body=None, method=None):
    headers = {'kbn-xsrf': 'elk-lab', 'Content-Type': 'application/json'}
    if user:
        headers['Authorization'] = 'Basic ' + base64.b64encode(f'{user}:{password}'.encode()).decode()
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, context=context, timeout=15)
    except urllib.error.HTTPError as exc:
        response = exc
    with response:
        status, raw = response.code, response.read()
    try:
        return status, json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return status, raw.decode(errors='replace')


def main():
    env, context = config(), client()
    es = 'https://localhost:' + env['ES_PORT'].rsplit(':', 1)[-1]
    kb = 'https://localhost:' + env['KIBANA_PORT'].rsplit(':', 1)[-1]
    web = 'https://localhost:' + env.get('WEB_PORT', '8443').rsplit(':', 1)[-1]
    checks = []

    def check(name, passed):
        checks.append({'check': name, 'passed': bool(passed)})
        print(('PASS ' if passed else 'FAIL ') + name, flush=True)
        if not passed:
            raise RuntimeError(name)

    for name, url in [('Elasticsearch', es), ('Kibana', kb + '/s/lab/api/data_views'), ('Nginx', web + '/')]:
        check(name + ' rejects unauthenticated requests', request(url, context)[0] == 401)
    check('Nginx serves authenticated requests', request(web + '/', context, 'demo', env['WEB_PASSWORD'])[0] == 200)
    check('Nginx denies private path', request(web + '/private/', context, 'demo', env['WEB_PASSWORD'])[0] == 403)

    for role in ['viewer', 'analyst']:
        user, password = 'lab_' + role, env['LAB_' + role.upper() + '_PASSWORD']
        check(user + ' can read lab data', request(es + '/lab-logs-*/_count', context, user, password)[0] == 200)
        check(user + ' can read lab dashboard', request(kb + '/s/lab/api/saved_objects/dashboard/elk-live', context, user, password)[0] == 200)
        check(user + ' cannot read the default space', request(kb + '/api/saved_objects/index-pattern/elk-lab', context, user, password)[0] == 403)
        status, privileges = request(es + '/_security/user/_has_privileges', context, user, password, {
            'cluster': ['manage_security'],
            'index': [{'names': ['lab-logs-*'], 'privileges': ['read', 'write', 'delete_index']}],
            'application': [{'application': 'kibana-.kibana', 'resources': ['space:lab'],
                             'privileges': ['feature_dashboard.read', 'feature_dashboard.all']}]
        })
        index = privileges.get('index', {}).get('lab-logs-*', {})
        app = privileges.get('application', {}).get('kibana-.kibana', {}).get('space:lab', {})
        check(user + ' has read-only Elasticsearch access', status == 200 and index.get('read') and not index.get('write') and not index.get('delete_index') and not privileges['cluster']['manage_security'])
        check(user + ' dashboard permission is scoped correctly', app.get('feature_dashboard.read') and app.get('feature_dashboard.all') == (role == 'analyst'))
    status, writer = request(es + '/_security/user/_has_privileges', context, 'logstash_ingest', env['LOGSTASH_PASSWORD'], {
        'cluster': ['manage_security'], 'index': [
            {'names': ['lab-logs-*'], 'privileges': ['write']},
            {'names': ['unrelated-*'], 'privileges': ['write']}]
    })
    check('Writer can write only lab indices and cannot manage security', status == 200 and writer['index']['lab-logs-*']['write'] and not writer['index']['unrelated-*']['write'] and not writer['cluster']['manage_security'])

    probe_code = """
import socket, ssl
context=ssl.create_default_context(cafile='/ca/ca/ca.crt')
try:
    with socket.create_connection(('logstash',5044),timeout=5) as sock:
        with context.wrap_socket(sock,server_hostname='logstash') as tls:
            tls.sendall(b'x')
            tls.recv(1)
except ssl.SSLError:
    print('rejected')
else:
    raise SystemExit('Client without certificate was not rejected by TLS')
"""
    check('Beats rejects clients without a client certificate', compose('exec', '-T', 'traffic', 'python', '-c', probe_code).strip() == 'rejected')
    monitor = compose('exec', '-T', 'logstash', 'bash', '-c', 'curl --silent --cacert config/certs/ca/ca.crt -o /dev/null -w "%{http_code}" https://localhost:9600/')
    check('Logstash monitoring rejects unauthenticated requests', monitor == '401')

    def search(body):
        status, data = request(es + '/lab-logs-*/_search?allow_partial_search_results=false', context,
                               'elastic', env['ELASTIC_PASSWORD'], body)
        check('Elasticsearch search completed without partial results', status == 200 and not data['timed_out'] and data['_shards']['failed'] == 0)
        return data

    live_query = {'term': {'log_origin.keyword': 'live'}}
    before = search({'size': 0, 'track_total_hits': True, 'query': live_query})['hits']['total']['value']
    token = '/verification-' + uuid.uuid4().hex
    started = time.monotonic()
    check('Unique real HTTPS request reaches Nginx', request(web + token, context, 'demo', env['WEB_PASSWORD'])[0] == 404)
    probe_query = {'bool': {'filter': [live_query, {'term': {'url.original.keyword': token}}]}}
    deadline = time.monotonic() + 30
    while True:
        status, response = request(es + '/lab-logs-*/_search?allow_partial_search_results=false', context,
                                   'elastic', env['ELASTIC_PASSWORD'], {'size': 1, 'query': probe_query})
        if status == 200 and response['hits']['hits']:
            break
        if time.monotonic() > deadline:
            raise RuntimeError('Real request was not searchable within 30 seconds')
        time.sleep(1)
    latency = round(time.monotonic() - started, 3)
    document = response['hits']['hits'][0]['_source']
    check('Real request indexed with parsed fields and authenticated TLS identity', document['tls']['client']['subject'] == 'CN=filebeat' and document['http']['response']['status_code'] == 404 and '_nginx_parse_failure' not in document.get('tags', []))
    after = search({'size': 0, 'track_total_hits': True, 'query': live_query})['hits']['total']['value']
    check('Live indexed count increases', after > before)
    status, health = request(es + '/_cluster/health', context, 'elastic', env['ELASTIC_PASSWORD'])
    check('Elasticsearch cluster is green', status == 200 and health['status'] == 'green')
    result = {'observed_at': datetime.now(timezone.utc).isoformat(), 'checks': checks,
              'live_count_before': before, 'live_count_after': after,
              'request_to_search_seconds': latency, 'sample_document': document,
              'browser_rendering_verified': False}
    (ROOT / 'reports/live-security.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Live records {before} -> {after}; unique request searchable after {latency}s', flush=True)


if __name__ == '__main__':
    main()
