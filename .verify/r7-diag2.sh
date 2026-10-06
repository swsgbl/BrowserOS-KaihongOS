#!/system/bin/sh
# P3 diag2: busybox-native HTTP probe from inside VM
echo "== busybox wget GET /mcp (expect 405) =="
busybox wget -T 5 -S -O /dev/null http://127.0.0.1:9222/mcp 2>&1 | head -8
echo "== busybox nc raw request =="
printf 'GET /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | busybox nc -w 5 127.0.0.1 9222 2>&1 | head -12
echo DONE_DIAG2
