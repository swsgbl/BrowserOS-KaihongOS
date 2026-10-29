# P66 验证报告：真实 AI Agent 矩阵——Claude Code / Codex / hmharness 全部装进 VM 并驱动本机浏览器

日期: 2026-10-29 12:00-14:00 | 设备: 192.168.161.137:10178（KaihongOS 6.1.2.08 musl/x86_64）| 执行: Zodex

## 结论: PASS —— 三大真实 agent 全部在 VM 内运行并通过 MCP loopback 驱动 BrowserOS

| Agent | 运行形态 | LLM 通道 | 浏览器控制 | 结果 |
|---|---|---|---|---|
| **hmharness**（并行工程今日已装，本次验证） | 原生（launcher v2：--jitless + vm-fetch polyfill） | GLM coding 直连 | 自写 MCP 客户端（原生 http+SSE 解析） | ✅ 12 轮/11 工具：建 tab→read→正确答案→**自主发现 P51 归属机制**并用原会话关 tab |
| **Claude Code 2.1.98**（本次安装） | 纯 JS 版（最新 2.1.312 已改原生二进制不可用；2.1.98=最后纯 JS）+ 自写 vm-fetch-full polyfill | 宿主 anthropic_relay:19224（Anthropic→OpenAI 翻译→GLM） | 原生 MCP（--mcp-config http 型） | ✅ 建 tab→example.com→标题+中文首段→**主动关闭自己的 tab** |
| **Codex 0.165.0**（本次安装） | **官方 musl 静态构建**（GitHub release codex-x86_64-unknown-linux-musl.tar.gz 110MB，npm 渠道只有 glibc 不可用） | 宿主 responses_relay:19225（Responses API→chat completions 翻译→GLM） | config.toml [mcp_servers] url 型 streamable-http | ✅ 建 tab→标题+英文首段→closed:true；自主探明非 CDP（/json 404）；**正确诊断 P51 拒绝关闭外来 tab（安全机制生效）** |
| vm_agent.js（P61 自研） | 原生 http | 宿主 llm_relay→agnes | 自带 | ✅ P61 已证 |

## 关键技术发现（VM 环境事实修正）

1. **VM node 必须 --jitless**（内核禁 RWX）→ jitless V8 无 WebAssembly → 内置 fetch 崩。hmh 安装器自带 vm-fetch polyfill；本阶段自写**完整版 vm-fetch-full.cjs**（Headers entries/iterator 等完整表面，Claude Code 需要）存 evidence/p66/。
2. **npm 在 VM 上崩溃**（V8 Check failed，jitless 也救不了）→ 一律走 **npmmirror tarball 直装**。
3. **Claude Code 2.1.312+（npm 最新）已是原生二进制壳**（29KB+下载器）——musl 不可用；**2.1.98 是最后纯 JS 版**（18MB cli.js，jitless 可跑）。
4. **Codex 官方 GitHub release 有 musl 静态构建**（npm optionalDeps 只有 glibc）；Rust 静态二进制在无 RWX 内核正常运行。
5. **GLM coding plan key 的边界**：`/api/coding/paas/v4`（OpenAI 协议）✅；`/api/anthropic`（通用 Anthropic 端点）401 ✗——所以 Claude Code/Codex 都需要**协议翻译中继**（本阶段交付 tools/anthropic_relay.js :19224 + tools/responses_relay.js :19225，宿主机运行，VM 经 192.168.161.1 访问）。
6. Claude Code root 下禁用 --dangerously-skip-permissions → `IS_SANDBOX=1` 解。
7. codex exec 需显式 `< /dev/null` 关 stdin。

## 安装配方（可复现）

- Claude Code：`.hm-tmp`→`evidence/p66/p66_install_claude.cjs`（npmmirror 元数据→最新纯 JS 版→tarball→tar 解包→jitless 冒烟）
- Codex：宿主 `curl -x socks5h://127.0.0.1:10808 -L -o codex-musl.tar.gz https://github.com/openai/codex/releases/download/rust-v0.165.0/codex-x86_64-unknown-linux-musl.tar.gz` → hdc file send → tar
- 两中继：`node tools/anthropic_relay.js` / `node tools/responses_relay.js`（宿主后台）
- VM 侧运行脚本全存 evidence/p66/（p66_claude_smoke3.sh / p66_codex_browser.sh / p66_codex_smoke3.sh）

## 证据

evidence/p66/：三 agent 的浏览器任务结果原文、hmh 的 19.9KB MCP 完整 JSON-RPC 日志与其自写客户端源码、安装器/polyfill/运行脚本、GLM 端点探测。

## 遗留

- 三 agent 依赖宿主双中继（GLM key 不通吃 Anthropic/Responses 协议）；VM 内自建翻译可后续做（非阻塞）。
- hmh@VM 由并行工程（hmh-desktop）维护，本报告只验证其浏览器控制能力。
