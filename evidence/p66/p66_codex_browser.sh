#!/system/bin/sh
# P66: Codex on VM drives local browser via MCP (streamable-http url server)
TOK=$(cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt)
GLMKEY=$(sed -n 's/.*"apiKey": "\([^"]*\)".*/\1/p' /data/local/home/.hmharness/config.json | head -1)
mkdir -p /data/local/home/.codex
cat > /data/local/home/.codex/config.toml <<EOF
model = "glm-5.3"
model_provider = "glmrelay"
model_reasoning_effort = "none"

[model_providers.glmrelay]
name = "GLM via responses relay"
base_url = "http://192.168.161.1:19225/v1"
env_key = "GLM_API_KEY"
wire_api = "responses"

[mcp_servers.browseros]
url = "http://127.0.0.1:9222/mcp?token=$TOK"
startup_timeout_sec = 20
EOF
export GLM_API_KEY="$GLMKEY"
export HOME=/data/local/home
cd /data/local/tmp
timeout 540 ./codex-install/codex-x86_64-unknown-linux-musl exec --skip-git-repo-check -s danger-full-access '使用 browseros MCP 服务器的工具：新建标签页打开 https://example.com ，等页面加载后读取页面内容，告诉我页面标题和第一段正文。完成后用 tabs close 关闭你打开的标签页。' < /dev/null 2>&1 | tail -30
