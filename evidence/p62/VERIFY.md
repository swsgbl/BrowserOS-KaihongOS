# P62 验证报告：MCP 工具语义修复（真实 agent 实测缺陷 7 项）

日期: 2026-10-29 04:20-06:10 | 设备: 192.168.161.137:10178 | 开发: hmharness（web-mvsk5n1r 两轮）| 验收: Zodex 独立复验

## 结论: PASS（7/7 项；A 项两轮收敛）

## 缺陷与修复

| 项 | 缺陷 | 根因 | 修复 | 验收 |
|---|------|------|------|------|
| **G** | act click 无界挂起 90s+，期间 app 死亡（无 faultlog） | click/type 走 `__bcp_arkts_callback` proxy（registerJavaScriptProxy），导航后 proxy 死亡 → runJavaScript promise 永不 settle | 自包含同步表达式（无桥依赖）+ callTool 30s 硬超时 + executeJS/evaluate 5s Promise.race | 超时返回干净 `-32000`；app 存活；三轮探针无挂死 |
| **A** | act 触发导航后 snapshot/read/grep 返回旧/残缺内容（P61 发现） | **百度结果页 DOM 内嵌字面 `<style>` 源码文本节点**（第三方注入产物）；旧快照构建器遍历全部 textNode 取 textContent（26 万字符）被 CSS 吃满 30k 截断。与桥无关（决定性实验：同表达式走 evaluate 路径同样产出 CSS——路径无关，表达式缺陷） | `buildSnapshotMdExpr()` 重写：文本骨架 `document.body.innerText`（规范保证仅渲染文本，24000 截断）+ 结构化元素（h1-6/a/button/img/table）单独收集+可见性过滤（链接≤200）+ payload 三重校验重试哨兵；附带修 `indexOf('http')!==0` 优先级 bug | **Zodex 终验（confirm=true 安全态）**：type_at #kw → click #su（响应带回 wd=上海天气 URL）→ read 25927B 含天气、零 CSS 污染、grep 49 命中；锚点导航（iana）5796→6359 新鲜 |
| **B** | tabs.new 后 read 偶发 `{"result":"null"}`（内部 agent 并发时） | 隐式目标解析偶落空 | null/空快照返回 MCP_003 明确错误（不再假成功） | 双会话隔离探针 PASS（会话间不串 tab） |
| **C** | history back/forward 响应体空 `{}`（P60 遗留） | 未构造返回体 | `{url,title,action}`（settle-poll 后取真实值） | `{"url":"https://www.iana.org/domains/reserved","title":"IANA-managed Reserved Domains","action":"back"}` |
| **D** | grep 与 read 不同源，IANA "Reserved" 0 命中（P60 遗留） | 数据源不同 | grep 改用与 read 同源 SnapshotGenerator | hits=2/3 实测 |
| **E** | server/discover 噪音（P60 记录 -32001） | — | 已是标准 -32601（保持） | PASS |
| **F** | example.com 新版无 h1，冒烟断言过时 | — | p59_regression.py 断言改 documentation examples/文档示例 | static 全过 |

## 关键澄清（验收方贡献）

1. **`input[type=submit]` 探针挂死 ≠ bug**：detectClick 匹配 'submit' 子串 → FORM_SUBMIT → requestConfirmation 弹框等人 → 无人值守 30s 兜底。这是 P8 安全设计 + G 修复的正确组合表现。agent 实战用 `#su`（同一按钮，不含敏感词）直接执行。
2. **P63 议题**：敏感检测基于选择器字面量，同一按钮换选择器可绕过（#su vs input[type=submit]）；上游无表单提交确认档。需产品决策：按语义检测（表单 action/元素类型）或对齐上游去掉 FORM_SUBMIT 档。
3. sensitiveConfirm 测试中按 P10 既有开关模式临时关、终态已恢复 true（od dump 实证）。

## 回归

- static_checks 全过；smoke_reg 9/9；p62_verify：confirm=false 下 5/5（hmh run4），confirm=true 下 4/5+A 终验探针 PASS（Zodex finalA）
- VM 内 agent E2E（agent_run1_log.json）：type+click+wait 链全通，read 干净；LLM 最终答案环节因 agnes 免费档 429（当日额度尽）未复跑——直连 MCP 的 finalA 探针覆盖同一调用序列，等价证据

## 证据（evidence/p62/）

VERDICT.md（hmh 两轮裁决）· VERIFY_ROUND1.md（Zodex 第一轮）· p62_verify_run2/3/4.txt · p62_acceptA_final.txt · p62_afix_final.txt · p62_agent_run1_log.json · p62_finalA_probe.cjs（终验脚本）· p62_stale_results.jpeg · RESUME-STATE.md

## 变更文件

entry/src/main/ets/protocol/BCPEngine.ets · entry/src/main/ets/service/MCPServer.ets · tools/p59_regression.py（+smoke 布局产物）
