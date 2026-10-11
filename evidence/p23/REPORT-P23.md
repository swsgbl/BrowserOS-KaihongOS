# P23 交付报告（2026-10-11，本棒完成）

## 交付总览

| Commit | 内容 | 验证 |
|--------|------|------|
| 094d97a feat(p23a) | 定时任务全链 | hilog init done + layout + 截图全绿 |
| bfd2d07 feat(p23b) | LLM Hub 多供应商 | layout + 截图全绿（真实 config 读取实证） |
| 8e3e8db docs(p23) | DEVPLAN P23 节 | - |

## Phase A：定时任务
- `service/ScheduleManager.ets`（新 316 行）：ScheduleTask 模型（hourly/daily/weekly + timeOfDay）、60s tick、AgentEngine.createAgent(ONCE) → 5s 轮询（120 次上限）→ getFinalAnswer 截 200 字写 lastResult/lastRunAt；runningRounds 防重入；maxAgents 拒绝记失败
- `pages/ScheduledTasksPage.ets`（新 470 行）：列表（Toggle 开关/立即运行/删除/结果摘要）+ 新建面板（频率 pill + 条件 timeOfDay）
- 挂点：EventBus.SCHEDULES_CHANGED、⋮ 菜单 group3 头插、EntryAbility init/stop、ic_schedule.svg（p11 三步同步 43 号）
- 实证：`[ScheduleManager] init done, tasks=0`（hilog）；ScheduledTasksPage layout `PAGE: pages/ScheduledTasksPage` + 标题/0 个/新建/空态四要素；截图 `evidence/p23/p23a-scheduled-page.jpeg`

## Phase B：LLM Hub
- AppConfig 增 `llmProviders`（JSON string）六处同步（接口/Update/类字段/toJSON/fromJSON 容错读/ConfigManager.set）
- `pages/LlmHubPage.ets`（新 430 行）：供应商列表（Key 掩码/当前标记/设为当前/编辑/删除）+ 添加编辑面板（http 前缀校验）
- 「设为当前」写回 llmBaseUrl/llmApiKey/llmModel 三生效字段，AgentEngine 零改动
- 双入口：SettingsPage AiSection 尾行 + AgentSidePanel 模型循环第 5 项
- 实证：设置 AI 区「管理供应商预设…」渲染 [508,578]；LlmHubPage layout（当前: https://apihub.agnes-ai.com/v1 —— 真实 config 读取）+ 截图 `evidence/p23/p23b-llmhub-page.jpeg`

## 本棒三大坑（已固化记忆）
1. **BrowserShell 双 case 'downloads'**：openBuiltinPage(1607) 与 onMenuAction(1761) 各有一组 case，node patch 盲插命中前者 → pushUrl 静默无效。定位法：用 `case 'settings'` 紧邻对（仅 onMenuAction 有 downloads→settings 相邻）。
2. **write_file 大文件截断注入**：ScheduleManager 首写出现脏串（"调度阉割占位"），写后必须 findstr 关键行抽查再继续。
3. **VM 多窗口点击漂移**：uitest 点击会落到别家窗口（oneaiterm/tty7），验证前先 `aa start` 拉回目标 app。

## 构建链（全绿）
harmony_build（clean 一次确保 CompileArkTS 重跑）→ `python tools/p11_add_svgs_v1.py` → `python tools/build_v1_hap.py` → `python tools/install_p8.py`

## 遗留（下棒可选）
- jtbd/command 等上游剩余 3 屏对标
- ScheduleManager 到点自动触发 e2e（isDue 纯函数已评审，init+手动链路已实证）
- LlmHubPage「测试连接」按钮（可复用 SettingsPage 的 LLMClient.chat ping）
