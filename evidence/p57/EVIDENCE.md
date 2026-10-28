# P57 证据汇总 — evaluate→evaluate_in_page + read 无脚本化

日期：2026-10-28 · 设备：192.168.161.137:10178 (KaihongOS 实机) · 基线：f272459 (v0.1.0-beta)

## 改动范围（上游 10caad1d→a7df59e 漂移对齐，仅两处）

### 1. evaluate → evaluate_in_page（重命名+别名兼容）
- `MCPServer.ets`：PAGE_TOOLS(L33)、registry(L345)、resolveAlias 增加 evaluate→evaluate_in_page(L143-146)、两处注释
- `McpJsonRpcCore.ets`：descriptor 改名+aliases:['evaluate'](L364-367)
- 兼容：旧客户端调 evaluate 走 resolveAlias → 同 handler，零破坏

### 2. read 无脚本化（snapshot 管线优先，JS 仅兜底）
- `MCPServer.ets handleRead`(L979+)：主路径改 SnapshotGenerator.generate()
  （结构化 bridge 提取 __bcp_snapshot_md，不构造任意页面 JS 表达式）
- selector 语义：先走 ref 过滤；JS querySelector 提取仅在 snapshot 失败时兜底
- 注入面收窄：read 不再每次构造 runJavaScript 表达式

## 验证结果

| 验证项 | 结果 |
|---|---|
| hvigor 构建 | BUILD SUCCESSFUL (6.7s) |
| API23 重打包 | 3791570 B 全 STORED |
| 设备端签名+安装 | sign-app success / install successfully |
| tools/list 17 工具含 evaluate_in_page | ✅ (aliases=["evaluate"]) |
| evaluate_in_page '1+2*3' | ✅ {"ok":true,"result":7} |
| evaluate 别名 document.title | ✅ "Example Domain" |
| read 无参数 | ✅ source:"snapshot" + 页面全文 |
| harness_compat_test.py | **40/40 PASS ×3 连跑** |
| smoke_reg.py 9 项 | **9/9 PASS**（此前 7/8 失败=设备周期锁屏污染 dump，非回归） |
| static_checks.py | 23/23 PASS |

## 同步修改的测试工具表
- tools/harness_compat_test.py UPSTREAM_TOOLS
- tools/mcp_client_e2e.py UPSTREAM_TOOLS

## 记录在案未做（brief 明示跳过）
- claw-app UI、Docker zoom、screencast socket（不在 P57 范围）

## 过程发现
- 设备周期性自动锁屏（~2min，power-shell timeout 设置对锁屏策略不完全生效）：
  解锁链 = power-shell wakeup → uinput 上滑 → uitest uiInput click 登录钮(640,646) → aa start。
  跑 smoke 前必须解锁，否则 dump 抓到锁屏界面产生假 FAIL（4/7/9 项连锁）。
- harness 首两轮各 1 项 snapshot FAIL（len~111）= example.com 4s 内偶发未加载完的时序抖动，
  针对性复现 8 会话×navigate→snapshot 全过，3 连跑 40/40 确认非回归。
