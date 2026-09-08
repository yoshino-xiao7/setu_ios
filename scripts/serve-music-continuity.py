#!/usr/bin/env python3
"""Loopback-only deterministic Range fixture server; never fetches remote sources."""
import argparse
import json
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('--mime', default='audio/mpeg')
parser.add_argument('--bytes-per-second', type=int, default=2 * 1024 * 1024)
parser.add_argument('--ignore-range', action='store_true')
parser.add_argument('--config', required=True, type=Path)
args = parser.parse_args()
size = args.source.stat().st_size

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def do_GET(self):
        start, end = 0, size - 1
        span = self.headers.get('Range')
        if span and not args.ignore_range:
            match = re.fullmatch(r'bytes=(\d+)-(\d*)', span)
            if not match:
                self.send_error(400); return
            start = int(match[1]); end = min(end, int(match[2]) if match[2] else end)
            if start >= size or end < start:
                self.send_response(416); self.send_header('Content-Range', f'bytes */{size}')
                self.send_header('Content-Length', '0'); self.end_headers(); return
        partial = span and not args.ignore_range
        self.send_response(206 if partial else 200)
        self.send_header('Content-Type', args.mime)
        self.send_header('Content-Length', str(end - start + 1))
        self.send_header('ETag', '"continuity-fixture-v1"')
        if partial:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        try:
            with args.source.open('rb') as source:
                source.seek(start)
                remaining = end - start + 1
                while remaining:
                    chunk = source.read(min(16384, remaining))
                    if not chunk: break
                    self.wfile.write(chunk); self.wfile.flush(); remaining -= len(chunk)
                    if args.bytes_per_second > 0: time.sleep(len(chunk) / args.bytes_per_second)
        except (BrokenPipeError, ConnectionResetError):
            pass
    def log_message(self, *_):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
args.config.write_text(json.dumps({'url': f'http://127.0.0.1:{server.server_port}/fixture.audio', 'bytes': size}))
server.serve_forever()
