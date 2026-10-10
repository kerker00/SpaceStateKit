#!/usr/bin/env python3
"""Exercise URLSession against real local HTTP, including a streaming oversized body."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, os, subprocess, threading, time

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_GET(self):
        try:
            if self.path == '/slow': time.sleep(2)
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

if __name__ == '__main__':
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    env=dict(os.environ, SPACESTATE_HTTP_TEST_URL=f'http://127.0.0.1:{server.server_port}')
    try:
        subprocess.run(['swift','test','--package-path',str(Path(__file__).resolve().parents[1]),'--filter','realHTTPTransport'],env=env,check=True)
    finally: server.shutdown(); server.server_close()
