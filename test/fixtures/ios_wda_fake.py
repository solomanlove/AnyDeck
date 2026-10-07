#!/usr/bin/env python3
"""本地假 CLI：验证真实子进程、HTTP 和清理，不访问设备。"""
import json
import os
import signal
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

args = sys.argv[1:]
with open(Path(__file__).with_suffix('.calls'), 'a') as calls:
    calls.write(json.dumps({'pid': os.getpid(), 'args': args}) + '\n')
if args[0] == 'apps':
    print(json.dumps([{'CFBundleIdentifier': 'com.anydeck.WebDriverAgentRunner.xctrunner',
                       'CFBundleName': 'WDA'}]))
elif args[0] == 'image':
    print('{}')
elif args[0] == 'runwda':
    signal.pause()
else:
    assert args[:3] == ['--source', '127.0.0.1', '--local']
    assert args[3] == '--udid'
    phone = args[4]
    port = int(args[5].split(':')[0])

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            self.respond()

        def do_POST(self):
            self.respond()

        def respond(self):
            self.rfile.read(int(self.headers.get('Content-Length', 0)))
            if self.path == '/session':
                value = {'sessionId': phone}
            elif self.path.endswith('/window/size'):
                value = {'width': 375, 'height': 667}
            elif self.path.endswith('/orientation'):
                value = 'PORTRAIT'
            else:
                value = None
            data = json.dumps({'value': value}).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    HTTPServer(('127.0.0.1', port), Handler).serve_forever()
