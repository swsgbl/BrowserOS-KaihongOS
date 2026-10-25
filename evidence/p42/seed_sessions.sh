#!/system/bin/sh
# P42-E: seed 3 sessions with distinct startTime, verify cleanup picks by time not name
BASE=/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/sessions
mkdir -p "$BASE"
echo '{"sessionId":"zzz_old_test","startTime":1000000000000,"endTime":1000000001000,"operations":[]}' > "$BASE/zzz_old_test.json"
echo '{"sessionId":"mmm_mid_test","startTime":1500000000000,"endTime":1500000001000,"operations":[]}' > "$BASE/mmm_mid_test.json"
echo '{"sessionId":"aaa_new_test","startTime":2000000000000,"endTime":2000000001000,"operations":[]}' > "$BASE/aaa_new_test.json"
echo SEEDED
ls -la "$BASE"
