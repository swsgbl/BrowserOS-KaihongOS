"""P40-B diag: raw MCP initialize response with wrong token to see error shape."""
import json, socket, sys
sys.stdout.reconfigure(encoding='utf-8')
body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}).encode()
for tok in ['x', 'mcp_default_token']:
    try:
        s = socket.create_connection(("192.168.161.137", 9222), timeout=10)
        req = ("POST /mcp?token=" + tok + " HTTP/1.1\r\nHost: h\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " + str(len(body)) + "\r\n\r\n").encode() + body
        s.sendall(req)
        d = b''
        while True:
            c = s.recv(65536)
            if not c:
                break
            d += c
        s.close()
        print('tok=%r ->' % tok, d.decode('utf-8', 'replace')[:400])
        print('---')
    except Exception as e:
        print('tok=%r ERR' % tok, e)
