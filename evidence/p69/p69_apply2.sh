#!/system/bin/sh
# P69 apply v2: system_update task WITH correct kind
TS=$(date +%s%3N 2>/dev/null || awk 'BEGIN{srand();print srand()*1000}')
DIR=/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/device_agent_tasks
HAP=/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/updates/browseros-1.1.1.hap
cat > "$DIR/dat_${TS}_888888.json" <<EOF
{"taskId":"dat_${TS}_888888","agent":"claude-code","kind":"system_update","prompt":"SYSTEM_UPDATE||path=${HAP}||sha256=133bc4f8eb94a81ec54453f45dcea1b6d83aadaa62afeb8ff33a9d1143b1146f||version=1.1.1","contextUrl":"","contextTitle":"","contextSelection":"","status":"pending","createdAt":${TS}}
EOF
chmod 666 "$DIR/dat_${TS}_888888.json"
echo "posted: dat_${TS}_888888"
