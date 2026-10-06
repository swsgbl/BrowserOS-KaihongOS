#!/system/bin/sh
# P3: verify installed abc contains new code marker
echo "== bundle dirs =="
ls -d /data/app/el1/bundle/public/com.browseros.kaihong* 2>&1
B=/data/app/el1/bundle/public/com.browseros.kaihong
ls "$B" 2>&1
echo "== find modules.abc =="
find "$B" -name 'modules.abc' 2>/dev/null
ABC=$(find "$B" -name 'modules.abc' 2>/dev/null | head -1)
echo "ABC=$ABC"
if [ -n "$ABC" ]; then
  echo "== grep markers in installed abc =="
  grep -c 'authToken persisted' "$ABC" 2>&1
  grep -c 'mcp_token' "$ABC" 2>&1
  grep -c 'getBasePath' "$ABC" 2>&1
  ls -l "$ABC"
fi
echo DONE_ABC_CHECK
