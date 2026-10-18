#!/usr/bin/env python3
"""Make real authenticated HTTPS requests; never write synthetic log records."""
import base64
import os
import ssl
import signal
import threading
import urllib.error
import urllib.request

context = ssl.create_default_context(cafile='/ca/ca/ca.crt')
credentials = base64.b64encode(('demo:' + os.environ['WEB_PASSWORD']).encode()).decode()
interval = float(os.environ.get('TRAFFIC_INTERVAL', '2'))
if interval < 0.2:
    raise SystemExit('TRAFFIC_INTERVAL must be at least 0.2 seconds')
paths = ['/', '/', '/missing', '/private/']
i = 0
stopping = threading.Event()
signal.signal(signal.SIGTERM, lambda *_: stopping.set())
signal.signal(signal.SIGINT, lambda *_: stopping.set())
while not stopping.is_set():
    path = paths[i % len(paths)]
    request = urllib.request.Request('https://nginx:8443' + path,
                                    headers={'Authorization': 'Basic ' + credentials,
                                             'User-Agent': 'ELK-Lab-Live-Client/1.0'})
    try:
        with urllib.request.urlopen(request, context=context, timeout=10) as response:
            status = response.status
    except urllib.error.HTTPError as exc:
        status = exc.code
        exc.close()
    except (urllib.error.URLError, OSError) as exc:
        print(f'Request failed: {exc}', flush=True)
        stopping.wait(interval)
        continue
    print(f'{path} -> HTTP {status}', flush=True)
    i += 1
    stopping.wait(interval)
