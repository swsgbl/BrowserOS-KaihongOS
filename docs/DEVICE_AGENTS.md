# 设备智能体（Device Agents）— BrowserOS P67

把 VM 上的 **Claude Code / Codex / hmharness** 接进应用的 AI 切换菜单（新标签页 provider pill 与右侧 Agent 侧栏）。

## 架构：收件箱模式（应用零进程依赖）

HarmonyOS 普通应用不能 spawn 子进程，因此采用收件箱模式：

```
应用 UI（选择器：内置智能体 + 设备智能体）
  └─ 提交任务 → 写沙盒 files/device_agent_tasks/<id>.json (pending)
                      ↑ MCP 工具 device_agent_tasks (next/complete)
设备智能体 runner（tools/device_agent_runner.js，VM 终端常驻）
  ├─ MCP agent_register 注册 + 30s 心跳（UI 在线点 = lastSeen < 2min）
  ├─ device_agent_tasks next 领任务（pending → running）
  ├─ 执行命令模板（{prompt} 替换，超时 10min，IS_SANDBOX=1）
  └─ complete 回写结果（截断 32KB）
```

应用侧每 5s 轮询注册表与任务态；任务完成回流成侧栏气泡。

## MCP 工具（21 工具表新增 2 项）

| 工具 | 参数 | 说明 |
|---|---|---|
| `agent_register` | `name`*, `kind` (claude-code\|codex\|hmharness\|custom) | 注册/心跳刷新 lastSeen |
| `device_agent_tasks` | `action=next`: `agent`*; `action=complete`: `taskId`*, `ok`, `result` | 领任务 / 回写结果 |

注册表持久化于 `files/device_agents.json`，断电恢复。

## 使用（VM 内）

```sh
# token（应用沙盒 files/mcp_token.txt 同值；部署脚本通常已放好）
cat /data/local/tmp/browseros_mcp_token

# Claude Code（P66 配方：IS_SANDBOX=1 + vm-fetch-full polyfill 由包装命令自带）
node /data/local/tmp/device_agent_runner.js --name claude-code --kind claude-code \
  --cmd "node --require /data/local/tmp/vm_fetch_full.cjs /data/local/tmp/claude-code-install/package/cli.js -p {prompt} --output-format text"

# Codex
node /data/local/tmp/device_agent_runner.js --name codex --kind codex \
  --cmd "node --require /data/local/tmp/vm_fetch_full.cjs /data/local/tmp/codex-install/bin/codex.js exec {prompt}"

# hmharness（宿主中继）
node /data/local/tmp/device_agent_runner.js --name hmharness --kind hmharness \
  --cmd "/usr/local/bin/hmh -p {prompt}"
```

参数：`--host`(默认 127.0.0.1) `--port`(9222) `--token-file` `--timeout-min`(10) `--poll-ms`(3000) `--log`。

## UI 行为

- 新标签页 provider pill 与侧栏模型下拉出现"设备智能体"分区：名称 + kind + 在线/离线点（绿=lastSeen<2min）。
- 选中后提交任务：写任务文件，显示"等待设备智能体执行…"，结果回流成 agent 气泡（>500 字截断）。
- 再次点击同项切回内置智能体；runner 下线后在线点变灰（注册表保留，断电恢复仍在）。

## 故障排查

- runner 日志：`/data/local/tmp/da_runner_<name>.log`
- 应用侧：hilog 过滤 `[P67]`
- MCP 401 → token 不匹配（对比 files/mcp_token.txt 与 --token-file）
- 任务一直 pending → runner 未注册同名 agent 或 MCP 会话失效（runner 自动重连）
