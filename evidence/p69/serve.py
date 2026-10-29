#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P69 验收：本地 HTTP 源（模拟国内/国际双仓）。端口 8931，根=evidence/p69/www/。"""
import http.server
import os
import socketserver

WWW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "www")
PORT = 8931


class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=WWW, **kw)

    def log_message(self, fmt, *args):
        print("[src]", self.address_string(), fmt % args, flush=True)


socketserver.TCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("192.168.161.1", PORT), H) as httpd:
    print(f"P69 test source serving {WWW} at http://192.168.161.1:{PORT}/", flush=True)
    httpd.serve_forever()
