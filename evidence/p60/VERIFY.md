# P60 验证报告: 真实 AI Agent 实测 (hmharness + Claude Code → KaihongOS 浏览器 MCP)

日期: 2026-10-28 23:33 | 设备: 192.168.161.137:10178 (KaihongOS 6.1.2.08 / API23)

## 结论: PASS

首次用真实 AI 代理驱动深开鸿浏览器完成端到端任务:
1. hmharness (裸 MCP 客户端) — 全链 10 步脚本通过 (run4/run5 日志)
2. 官方 MCP TS SDK (latest, StreamableHTTPClientTransport) — CONNECT OK + 17 工具 + tabs/navigate/read PASS
3. Claude Code 2.1.311 (claude -p --mcp-config) — 真实任务完成:
   建 tab → example.com (报告标题+正文) → IANA (总结保留域名) → 主动关闭任务标签
   (initialize instructions 的 "Tidy up" 指引被遵守)

## 实测挖出并修复的 3 个互操作 bug (McpJsonRpcCore/HttpMcpTransport)

| # | 症状 | 根因 | 修复 |
|---|------|------|------|
| 1 | Claude Code ZodError: jsonrpc expected "2.0" / id expected string | 通知(notifications/initialized 无 id)返回 error body (id:null) | P60: rpcId===null → 202 + 空 body |
| 2 | 官方 SDK ZodError: Unrecognized key "error" | success 响应携带 "error":null 尾巴 | P60: outcome() 手工 JSON, success/error 各只含自己的键 |
| 3 | 官方 SDK ZodError: capabilities.prompts/resources expected object received null | 显式 null 字段 | P60: 删除 null 字段 (键缺省即合法) |

另修 1 个 netstack 崩溃: sendSimple 空 body 时 encodeInto('') 返回 undefined → 500;
空 body 只发 header 字节 (P60 patch3)。

## 链路

fport tcp:19222→9222 (guest 127.0.0.1:9222, P42 KAI-047 loopback-only)
token: /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt (每次重启轮换)

## 遗留发现 (DEVPLAN)

- history back/forward 返回体空 {} (功能生效, evaluate location.href 可证)
- grep 工具在 IANA 页 pattern "Reserved" 0 命中 (read 文本可见) — 待查
- Claude Code 探测性发 server/discover → 收 -32001 后回退 initialize (无害, 但可优化为静默)
- 新版 example.com 无 h1, 冒烟断言应用 "documentation examples"/"文档示例"

## 证据文件

- evidence/p60/p60_agent_run4_log.json — hmharness 10 步全链
- evidence/p60/p60_agent_run5_log.json — hmharness run5 (evaluate/history/tabs list)
- evidence/p60/p60_layout_foreground.json — uitest dumpLayout, 标签栏与 MCP tabs list 一致
- evidence/p60/p60_screen_*.jpeg — VM 屏幕截图
- .hm-tmp/p60_hilog_final.txt — hilog: Claude Code 会话 886ca8ed 全程 RPC
- .hm-tmp/sdkprobe/probe2.cjs — 官方 SDK 探针 (PASS)
- 源码修改: entry/src/main/ets/service/{McpJsonRpcCore,HttpMcpTransport}.ets (P60 标记)
