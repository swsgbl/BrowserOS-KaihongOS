#!/system/bin/sh
# VM 内 TCP 探测：nc 或 /dev/tcp
if command -v nc >/dev/null 2>&1; then
  echo "GET /api/tags HTTP/1.0" | nc -w 3 10.0.2.2 11434 | head -5
  echo "NC_EXIT=$?"
else
  echo "no nc"
  timeout 3 sh -c 'echo > /dev/tcp/10.0.2.2/11434' 2>&1
  echo "TCP_EXIT=$?"
fi
