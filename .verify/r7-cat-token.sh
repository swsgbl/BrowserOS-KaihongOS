#!/system/bin/sh
# P3: locate app files dir & cat mcp_token.txt
BASE=/data/app/el2/100/base/com.browseros.kaihong
echo "== ls $BASE =="
ls "$BASE" 2>&1
echo "== ls $BASE/haps =="
ls "$BASE/haps" 2>&1
echo "== ls $BASE/haps/entry =="
ls "$BASE/haps/entry" 2>&1
echo "== ls files =="
ls "$BASE/haps/entry/files" 2>&1
echo "== cat token =="
cat "$BASE/haps/entry/files/mcp_token.txt" 2>&1
echo "== alt: find token =="
find /data/app/el2/100/base -name 'mcp_token.txt' 2>/dev/null
echo DONE_LOCATE
