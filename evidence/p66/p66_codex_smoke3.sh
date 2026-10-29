#!/system/bin/sh
# P66: Codex smoke v2b — stdin closed
GLMKEY=$(sed -n 's/.*"apiKey": "\([^"]*\)".*/\1/p' /data/local/home/.hmharness/config.json | head -1)
export GLM_API_KEY="$GLMKEY"
export HOME=/data/local/home
cd /data/local/tmp
timeout 300 ./codex-install/codex-x86_64-unknown-linux-musl exec --skip-git-repo-check -s danger-full-access '只回复两个字：成功' < /dev/null 2>&1 | tail -12
