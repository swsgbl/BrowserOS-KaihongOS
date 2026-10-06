#!/system/bin/sh
# P3 diag: probe 9222 from inside VM + hilog watch
echo "== tools =="
command -v curl && echo HAS_CURL
command -v nc && echo HAS_NC
command -v wget && echo HAS_WGET
command -v busybox && echo HAS_BUSYBOX
echo "== netstat 9222 =="
netstat -tln 2>/dev/null | grep 9222
echo "== curl probe (5s timeout) =="
curl -m 5 -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9222/mcp 2>&1
echo ""
echo DONE_DIAG
