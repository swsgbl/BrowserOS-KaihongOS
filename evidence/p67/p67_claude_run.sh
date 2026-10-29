#!/system/bin/sh
# P67: claude wrapper for device_agent_runner (short template; full env inside)
P="$1"
T=$(cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt)
G=$(sed -n 's/.*"apiKey": "\([^"]*\)".*/\1/p' /data/local/home/.hmharness/config.json | head -1)
printf '{"mcpServers":{"browseros":{"type":"http","url":"http://127.0.0.1:9222/mcp?token=%s"}}}' "$T" > /data/local/tmp/da_mcp.json
export ANTHROPIC_BASE_URL=http://192.168.161.1:19224
export ANTHROPIC_API_KEY="$G"
export ANTHROPIC_MODEL=glm-5.3
export ANTHROPIC_SMALL_FAST_MODEL=glm-5.3
export DISABLE_TELEMETRY=1
export DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export IS_SANDBOX=1
export NODE_OPTIONS="--jitless --require /data/local/tmp/vm-fetch-full.cjs"
timeout 540 node /data/local/tmp/claude-code-install/package/cli.js -p "$P" --mcp-config /data/local/tmp/da_mcp.json --dangerously-skip-permissions < /dev/null 2>&1 | tail -30
