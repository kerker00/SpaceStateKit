#!/usr/bin/env python3
"""Exercise URLSession against real local HTTP, including a streaming oversized body and server-sent events."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, os, subprocess, threading, time

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_GET(self):
        try:
            if '/v1/stream' in self.path: return self.stream()
            if self.path == '/slow': time.sleep(2)
            if self.path == '/cookie':
                body = json.dumps({'space': 'Cookie returned' if self.headers.get('Cookie') else 'No cookie', 'state': {'open': True}}).encode()
                self.send_response(200); self.send_header('Set-Cookie', 'probe=1; Path=/'); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body); return
            if self.path == '/redirect':
                self.send_response(302); self.send_header('Location', '/ok'); self.send_header('Content-Length', '0'); self.end_headers(); return
            if self.path == '/oversize':
                self.close_connection = True
                self.send_response(200); self.send_header('Connection', 'close'); self.send_header('Content-Length', '10000000'); self.end_headers(); self.wfile.write(b'x'*4096); self.wfile.flush(); return
            if self.path == '/chunked':
                self.send_response(200); self.send_header('Transfer-Encoding', 'chunked'); self.end_headers()
                for _ in range(100):
                    self.wfile.write(b'400\r\n' + b'x'*1024 + b'\r\n'); self.wfile.flush(); time.sleep(.01)
                self.wfile.write(b'0\r\n\r\n'); return
            body = b'x'*300000 if self.path == '/large' else json.dumps({'space':'Test Space','state':{'open':True}}).encode()
            self.send_response(503 if self.path == '/error' else 200)
            self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass

    def chunk(self, text):
        data = text.encode()
        self.wfile.write(b'%x\r\n' % len(data) + data + b'\r\n'); self.wfile.flush()

    def stream(self):
        """Server-sent events like SpacePush: /missing answers 404, /quiet goes silent, others send two changes a second apart."""
        if self.path.startswith('/missing/'):
            body = json.dumps({'error': 'unknown_space'}).encode()
            self.send_response(404); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body); return
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.send_header('Transfer-Encoding', 'chunked'); self.end_headers()
        self.chunk('retry: 1000\n\n')
        if self.path.startswith('/quiet/'): time.sleep(3); return
        for state in ('open', 'closed'):
            event = {'endpoint': 'https://a.example/', 'room': 'space', 'name': 'A', 'from': 'x', 'to': state, 'at': 1}
            self.chunk('event: change\ndata: ' + json.dumps(event) + '\n\n')
            time.sleep(1)
        self.chunk(''); self.close_connection = True

if __name__ == '__main__':
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    env=dict(os.environ, SPACESTATE_HTTP_TEST_URL=f'http://127.0.0.1:{server.server_port}')
    try:
        subprocess.run(['swift','test','--package-path',str(Path(__file__).resolve().parents[1]),'--filter','realHTTPTransport|realEventStream'],env=env,check=True)
    finally: server.shutdown(); server.server_close()
