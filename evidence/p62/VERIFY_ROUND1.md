# P62 验收方（Zodex）独立复验记录 — 第一轮（hmh 交付后、A 残留修复前）

日期: 2026-10-29 05:05-05:15 | 设备: 192.168.161.137:10178 | 构建: hmh p62-entry.hap (3817685B, all-STORED)

## 结论: 6/7 项验证通过；A 残留已精确定位并转 hmh 续跑修复

| 项 | 结果 | 证据 |
|---|------|------|
| G act 无界挂起+app 死亡 | ✅ 修复确认 | 根因=click/type 走 `__bcp_arkts_callback` proxy，导航后 proxy 死亡致 runJavaScript 永不 settle。修法=自包含同步表达式 + callTool 30s 硬超时 + executeJS/evaluate 5s race。实测：超时返回干净 `-32000 "P62: tool act timed out after 30s"`，app 存活（探针继续可用） |
| B read-null | ✅ PASS | 双会话隔离探针（p62_verify B-read-session-owned）；null 场景现返回 MCP_003 明确错误 |
| C history 空 body | ✅ PASS | `{"url":"https://www.iana.org/domains/reserved","title":"IANA-managed Reserved Domains","action":"back"}` |
| D grep 0 命中 | ✅ PASS | hits=2（同 SnapshotGenerator 源） |
| E server/discover | ✅ PASS | -32601 Method not found |
| F 冒烟断言 | ✅ | p59_regression.py:38 改 documentation examples/文档示例；static 全过 |
| A stale snapshot | 🟡 半修 | **锚点导航 OK**（iana a[href='/domains'] 点击→snapshot 1474→2681B 全新内容，脚本 .hm-tmp/p62_afix.cjs）；**表单提交导航仍残缺**（见下） |

## A 残留精确定位（供 hmh 续跑）

E2E agent 实测（evidence/p62/p62_agent_run1_log.json）：
- agent `act click #su`（LLM 自选 id，不含 'submit' 关键词不触发 FORM_SUBMIT 确认）→ **click 响应自带结果页 URL**（`wd=%E4%B8%8A%E6%B5%B7%E5%A4%A9%E6%B0%94`=上海天气，hmh 的 pageInfoAfterTransition 工作正常）→ 导航真实发生
- 但随后 read/grep 返回 **1556B 残缺快照**（仅 `<style data-for="result">` 片段）——与 P61 run3 同款；grep 天气/°C 0 命中
- 根因方向：snapshot/read/grep 管线仍依赖 `__bcp_snapshot_md` proxy 桥，表单提交导航后桥死亡/未重注入（与 G 同族根因）
- 视觉证据：P61 p61_run3_screen.jpeg 已证结果页真实渲染（天气卡片可见）

## 重要发现：sensitiveConfirm 与 FORM_SUBMIT 设计

- 探针 A 用 `input[type='submit']` → detectClick 匹配 'submit' 子串 → FORM_SUBMIT → requestConfirmation 弹框等人 → 无人值守 30s 兜底超时（干净报错，G 修复的正确表现）。**这不是 bug 是 P8 期安全设计**。
- P61 run3 / 本轮 E2E 能过是因为 LLM 用了 `#su`（同一按钮！）——不匹配敏感词 → 直接执行。
- **设计缺口转 P63**：检测基于选择器字面量，同一按钮换个选择器即绕过（#su vs input[type=submit]）。上游无表单提交确认；需要产品决策（按语义/表单类型检测，或对齐上游去掉 FORM_SUBMIT 档）。
- 设备当前 sensitiveConfirm=false（Zodex 测试态，P10 既有开关模式）；hmh 最终装机前恢复 true。

## 环境备注

- agnes 免费档 429：本轮 E2E step 11 再次触发（当日额度尽），不影响直连 MCP 探针验证。
- hmh daemon 本日崩过一次（04:15-04:19），P62 派发在其恢复后完成。
