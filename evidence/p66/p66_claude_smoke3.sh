#!/system/bin/sh
# P66: Claude Code smoke v3 — via host anthropic relay (Anthropic->OpenAI translation, GLM backend)
GLMKEY=$(sed -n 's/.*"apiKey": "\([^"]*\)".*/\1/p' /data/local/home/.hmharness/config.json | head -1)
export ANTHROPIC_BASE_URL=http://192.168.161.1:19224
export ANTHROPIC_API_KEY="$GLMKEY"
export ANTHROPIC_MODEL=glm-5.3
export ANTHROPIC_SMALL_FAST_MODEL=glm-5.3
export DISABLE_TELEMETRY=1
export DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export NODE_OPTIONS="--jitless --require /data/local/tmp/vm-fetch-full.cjs"
cd /data/local/tmp
timeout 330 node /data/local/tmp/claude-code-install/package/cli.js -p '只回复两个字：成功' < /dev/null 2>&1 | tail -6
