#!/system/bin/sh
# P3: stat installed hap + bm dump installTime
H=/data/app/el1/bundle/public/com.browseros.kaihong/entry.hap
ls -l "$H"
md5 "$H" 2>/dev/null || true
echo "== bm dump =="
bm dump -n com.browseros.kaihong | grep -E 'installTime|updateTime|versionCode|versionName|appId' | head -8
echo DONE_HAP_STAT
