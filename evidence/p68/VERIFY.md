# P68 补跑 — 验证与巡扫报告

日期:2026-10-29 · 设备:192.168.161.137:10178 · 基线:d0e923d + 06a8a9e (P67)

## 本棒改动(唯一代码缺口)

**handleSnapshot settle 重试接线** — `entry/src/main/ets/service/MCPServer.ets:910`
d0e923d 已把 read 的过渡态 settle(<3s 导航窗内空快照 → 500ms 后重试一次)落地,但 handleSnapshot
漏接:导航后立即 snapshot 会把空 content 直接返回给 LLM。本棒补上同款守卫:仅当 content 为空/null/
undefined 且 `BCPEngine.msSinceLastNav() < 3000` 时 settle 500ms 重试一次;重试结果仍空则保持原语义
(不改正常路径)。重试只在有内容时覆盖(避免用第二次空结果覆盖首次 refs)。

## 已在树里的 P68 修复(d0e923d,勿重做 — 本棒核实)

- BCPEngine executeJS/evaluate race 定时器 clearTimeout(孤儿定时器泄漏)+ lastNavAt 基础设施
- MCPServer 30s 工具级 race 定时器 clearTimeout + evaluate 10s 定时器 clearTimeout
- wait(ms) → `{ms, waited:true}`;wait(selector) → 显式 `found` 布尔(超时如实报错)
- read 的过渡态 settle 重试

## 巡扫结果(第 3 项)

| 项 | 结论 |
|---|---|
| i18n zh/en 对称 | 544/544 对称,无缺失、无重复键 |
| @StorageProp 带 @Watch | 全库零缺失(P26/P44 陷阱不存在) |
| setInterval/clearInterval | 全部文件配平,无泄漏 |
| 空 catch | 16 处,抽查全为 JSON 解析回退/重试环/fire-and-forget 注入,语义明确无需改 |
| console.log | static_checks 通过(全库 console.info) |

## 回归验证

| 验证 | 结果 |
|---|---|
| `python tools/p68_verify.py` | 4/4 PASS(wait 两分支 / 5x evaluate 快settle / read 过渡态) |
| `python tools/p68_b_verify.py`(本棒新增) | 2/2 PASS(snapshot 过渡态非空 971 字符 / 100x evaluate 压测 0 失败 51.8s) |
| `python tools/static_checks.py` | 全部通过 |
| `python tools/smoke_reg.py` | 9/9 PASS |
| `python tools/mcp_client_e2e.py` | 18/18 PASS(含限流恢复、WS 传输) |
| `python tools/p68_p67_regr.py`(本棒新增) | 4/4 PASS(tools/list 21 含 P67 对、agent_register、device_agent_tasks next/complete 错误路径) |

## P67 UI 不回退说明

设备智能体区在 AI 面板切换菜单(P67 已有截图证据 p67_dropdown.jpeg/dropdown2.jpeg);
本棒零 UI 代码改动,BrowserShell.ets/AgentSidePanel.ets 未触碰,MCP 层 P67 工具链 4/4 验证通过,
UI 无回归面。

## 装机链

`python tools/build_api23_hap.py` → `python tools/install_p68.py`(VM 内 hap-sign-tool 签名 + bm install)
