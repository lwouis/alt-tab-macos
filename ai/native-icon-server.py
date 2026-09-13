#!/usr/bin/env python3
"""Disposable loopback-only fixture server; no browser data or external requests."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit
import json, threading, time
ROOT = Path(__file__).parent / 'native-icon-fixtures'
counts, lock = {}, threading.Lock()
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path = urlsplit(self.path).path
        with lock:
            if path != '/stats': counts[path] = counts.get(path, 0) + 1
        if path == '/stats':
            with lock: body = json.dumps(counts).encode()
        elif path == '/redirect.html':
            self.send_response(302); self.send_header('Location', '/native-blue.html'); self.end_headers(); return
        elif path == '/external.html':
            self.send_response(302); self.send_header('Location', 'https://example.com/'); self.end_headers(); return
        elif path in ['/large.html', '/stream-large.html']: body = b'x' * (2 * 1024 * 1024)
        elif path == '/loop.html':
            self.send_response(302); self.send_header('Location', '/loop.html'); self.end_headers(); return
        elif path == '/race.png':
            time.sleep(3); body = (ROOT / 'native-red.png').read_bytes()
        elif path.endswith('.png') and (ROOT / path[1:]).is_file(): body = (ROOT / path[1:]).read_bytes()
        elif path.endswith('.html'):
            if path == '/slow.html': time.sleep(.6)
            color = 'blue' if 'blue' in path else 'red'
            icon = '' if path == '/missing.html' else f'<link rel="icon" href="/native-{color}.png">'
            if path == '/race.html': icon = '<link rel="icon" href="/race.png">'
            body = (f'<!doctype html><title>Native icon fixture</title>{icon}<h1>{path}</h1>'
                    '<a href="/native-red.html">Red</a> <a href="/native-blue.html">Blue</a> '
                    '<a href="/slow.html">Slow red</a> <a href="/missing.html">Missing</a>').encode()
            if path == '/race.html': body += b'<script>setTimeout(() => location.replace("/native-blue.html"), 750)</script>'
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200)
        self.send_header('Content-Type', 'image/png' if path.endswith('.png') else 'text/html')
        if path != '/stream-large.html': self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
ThreadingHTTPServer(('127.0.0.1', 18769), Handler).serve_forever()
