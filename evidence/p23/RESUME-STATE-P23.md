# P23 断点（上下文耗尽，侦查完毕、代码零写入）

任务书 `.zcode/p23_brief.md` 已读毕；git 基点 2cd4610，工作树净（仅 untracked `0)` 和 `smoke_reg_layout.json`，勿提交）。
本文固化全部侦查结论，下棒直接按「执行序」写码。

## 一、现状事实（已核实，勿重复侦查）

### AgentEngine.ets（service/）
- 单例 `export const AgentEngine = new AgentEngineImpl()`
- `createAgent(name, targetUrl, taskDescription, runStrategy=RunStrategy.ONCE): AgentConfig|null` —— 创建即开跑（runAgentTask 异步）；超 maxAgents 返 null
- `getFinalAnswer(agentId): string|null`（P19a 终态答案库：完成=finalAnswer / 失败='任务失败: '+reason）
- 状态流转 setAgentRunning/Completed/Error；runAgentTask 结束后 finalAnswers 必有值
- RunStrategy 从 `../common/Types` import

### ConfigManager（storage/，单例 ConfigManager）
- `get(): AppConfig` / `update(AppConfigUpdate): Promise<boolean>`（set+save，save 会 validate 并 emit CONFIG_CHANGE）
- AppConfig 字段全在 model/AppConfig.ets：toJSON/fromJSON 手工逐字段（加新字段三处：interface AppConfigJSON + class 属性 + toJSON + fromJSON 容错读）+ AppConfigUpdate 接口 + ConfigManager.set() 加分支
- llm 三件套：llmBaseUrl/llmApiKey/llmModel + sanitizeLlmBaseUrl 清洗

### StorageManager（storage/）
- `saveJSON(path, obj)/loadJSON(path)` 基于 basePath（EntryAbility onCreate 已 setBasePath(context.filesDir)）
- config.json 即此机制；schedules 可用 `schedules.json` 同路径直存

### EventBus（infra/）
- on/off/emit；EventBusEvents 静态类需加 `SCHEDULES_CHANGED = 'schedules_changed'`

### 页面模式（BookmarksPage 为模板）
- @Entry @Component + @StorageProp('darkMode') + pal() = Palette.of(this.darkMode)
- 返回按钮 Image($r('app.media.ic_back')) + router.back()；空态/Scroll+ForEach+Divider '#F1F3F4'
- 订阅模式：aboutToAppear EventBus.on / aboutToDisappear off，箭头函数属性存 handler 引用

### ⋮ 菜单（components/ChromeWidgets.ets ThreeDotMenu）
- group1/2/3 MenuEntry 数组；group3=[设置/查找/帮助]。加「定时任务」→ group3 头插 `{icon:$r('app.media.ic_schedule'),label:'定时任务',action:'scheduled_tasks'}`
- BrowserShell.onMenuAction switch 加 `case 'scheduled_tasks': router.pushUrl({url:'pages/ScheduledTasksPage'})`

### SettingsPage
- navItems 6 项（search/ai/appearance/privacy/mcp/about）左导航 index 分发
- AiSection = LLM 表单（BaseUrl/Key/Model + 保存/测试连接——测试逻辑可复用：LLMClient.chat({baseUrl,apiKey,model,messages:[user('ping')],tools:[],timeoutMs:15000}) + lastError）
- B 入口：AiSection 头部（CardShell 之后）加「LLM Hub」行：当前供应商名 + 「进入」按钮 router.pushUrl pages/LlmHubPage

### AgentSidePanel.ets
- 模型下拉是**简化点击循环**（modelOptions 数组 + modelSelection state，点击取模循环），非真下拉。B 的「管理供应商…尾项」：在 modelOptions 数组尾部 push '管理供应商…'，onCliick 处若 selection==末位则 router.pushUrl('pages/LlmHubPage')（第 233-245 行区域）

### main_pages.json
- 现有 8 页，追加 "pages/ScheduledTasksPage" 和 "pages/LlmHubPage"（第 9、10 位——任务书写 12/13 页是上游口径，本仓 8 页起步）

### 图标（resources/base/media/）
- 现有 42 个 ic_*.svg，**无 ic_schedule、无 ic_hub/ic_provider 类**。菜单项与页面需要：
  - ic_schedule.svg（定时任务菜单+页面标题图标）
  - ic_hub.svg（LLM Hub 用，可选——SettingsPage 行可复用 ic_robot）
- 新 svg 必须走 tools/p11_add_svgs_v1.py 三步同步（svg→ids→rebuild），否则 $r() 失败蓝方块（P11 固化坑）
- 现成可复用：ic_list（列表兜底）、ic_settings、ic_check（使用中标记）、ic_robot

### EntryAbility
- onCreate：setBasePath → HistoryManager/LoginStateManager/SessionManager.load → ConfigManager.load().then(MCP start)
- 定时器 tick 挂载点：ConfigManager.load().then 回调内（config 就绪后）调 ScheduleManager.init()

## 二、设计定案（与任务书对齐）

### A. ScheduleManager.ets（service/）
```ts
export class ScheduleTask { id,name,prompt,targetUrl, interval:'hourly'|'daily'|'weekly', timeOfDay:'HH:mm', enabled, lastRunAt:number, lastResult }
```
- Preferences：用 StorageManager.saveJSON/loadJSON('schedules.json')（数组包 {"tasks":[...]}，避免根数组解析问题）
- load() 在 init 时读回；每次变更 save
- tick：setInterval 60s，规则：
  - hourly: now-lastRunAt >= 3600_000
  - daily: timeOfDay 到点且今日未跑（lastRunAt 不在今天该时刻之后）
  - weekly: 周一且 timeOfDay 到点未跑（getDay()==1）
- 到点 → runNow(task)：AgentEngine.createAgent(name, targetUrl, prompt, ONCE)；轮询 status（或监听 AGENT_STATUS_CHANGE）终态后 getFinalAnswer 截 200 字写 lastResult + lastRunAt=Date.now() + save + emit SCHEDULES_CHANGED
- 防重入：running 标记 per task id
- 注意 createAgent 受 maxAgents(默认5)限制——超限时 lastResult 记 '失败：代理数已达上限'
- 注意：任务描述即 prompt；空 targetUrl 可（createAgent 允许 ''）

### A. ScheduledTasksPage.ets（pages/）
- 结构照 BookmarksPage：头部(返回+标题+计数+新建按钮) + 空态 + Scroll 列表
- ScheduleCard：名称/频率文案(hourly=每小时/daily=每天 HH:mm/weekly=每周一 HH:mm)/Toggle enabled/上次运行时间(fmtTime)/lastResult 2行(maxLines 2)/「立即运行」「删除」文字钮
- NewScheduledTaskDialog：页内条件渲染面板（项目风格无 CustomDialog，SettingsPage clearShowConfirm 同款 if 块）：名称 TextInput/任务描述 TextArea/目标URL TextInput/频率 3 个单选 pill(hourly/daily/weekly)/timeOfDay TextInput(daily|weekly 时显示, placeholder '09:00')
- 保存校验：名称+描述非空；立即持久化+emit
- fmtTime: lastRunAt==0→'从未'，否则 toISOString().substring(11,16) 当地时间…… 用 new Date(ts).toLocaleTimeString() 或手拼 HH:mm

### B. AppConfig 扩展
- `llmProviders: string = ''`（JSON 数组字符串）。AppConfigJSON/toJSON/fromJSON 三处 + AppConfigUpdate + ConfigManager.set 分支（原样存，trim）
- 解析辅助放 LlmHubPage 或 ConfigManager：`getLlmProviders(): LlmProviderRow[]`（id,name,baseUrl,apiKey,model,addedAt；JSON.parse 容错 try/catch 返 []）

### B. LlmHubPage.ets（pages/）
- 头部(返回+标题 LLM Hub+添加按钮) + 供应商行 HubProviderRow：名称/端点截断(maxLines 1 Ellipsis)/模型/「使用中」标记(baseUrl+model 与 cfg.llmBaseUrl/llmModel 全等)/设为默认/测试连接/删除
- 测试连接复用 SettingsPage 逻辑：LLMClient.chat({baseUrl: p.baseUrl, apiKey: p.apiKey, model: p.model, messages:[LLMChatMessage.user('ping')], tools:[], timeoutMs:15000})；行内 hint state（testingIdx/okIdx/failMsg）
- 设为默认：ConfigManager.update({llmBaseUrl:p.baseUrl, llmApiKey:p.apiKey, llmModel:p.model})，标记自动刷新（全等判断）
- 删除：过滤后写回 llmProviders
- AddHubProviderDialog：名称/端点/Key/模型 4 个 TextInput + 保存取消（页内 if 面板）
- id: `prov_${Date.now()}`

### B. SettingsPage AiSection 顶部加行
- CardShell 之后：Row{ Text('LLM Hub · 多供应商管理') + 当前供应商名(cfg.llmBaseUrl 空时'未配置'，否则 host 部分) + Button('进入')→pushUrl pages/LlmHubPage }

### B. AgentSidePanel 下拉尾项
- modelOptions 尾 push '管理供应商…'；onClick 循环逻辑改为：若点后 selection==尾位 → router.pushUrl('pages/LlmHubPage') 并不循环（import router @kit.ArkUI，检查该文件是否已 import）

## 三、构建链（红线，全套照旧）
1. `harmony_build`（或既有命令）→ 产物 entry hap
2. 新增 svg 后：`python tools/p11_add_svgs_v1.py`（三步：sync svg→ids→rebuild）
3. `python tools/build_v1_hap.py`（repack v1 HAP）
4. `python tools/install_p8.py`（hdc 127.0.0.1:15566 装机，不卸载不重启 VM）
- 参考最近一次成功链：P11-F/P21 均此链。devtools python 环境：直接 `python`（此前脚本均如此跑）

## 四、执行序（下棒照此做，每 Phase 构建装机 commit）
1. **Phase A（feat(p23a): scheduled tasks）**：
   a. EventBus 加 SCHEDULES_CHANGED
   b. service/ScheduleManager.ets 全量新文件
   c. pages/ScheduledTasksPage.ets 全量新文件
   d. main_pages.json 加页
   e. ChromeWidgets group3 加菜单项 + BrowserShell onMenuAction 加 case
   f. EntryAbility onCreate ConfigManager.load().then 内加 ScheduleManager.init()
   g. ic_schedule.svg 新建 → build → p11_add_svgs_v1 → build_v1_hap → install → 自测（建 hourly 任务→立即运行→列表见时间+结果→重启应用任务仍在）
   h. 证据存 evidence/p23/（hilog 片段+截图文件名建议 p23a-*.jpeg）
   i. commit feat(p23a): scheduled tasks
2. **Phase B（feat(p23b): llm hub）**：
   a. AppConfig 加 llmProviders 四处 + ConfigManager set 分支
   b. pages/LlmHubPage.ets 全量新文件
   c. main_pages.json 加页
   d. SettingsPage AiSection 加 Hub 行
   e. AgentSidePanel modelOptions 尾项+跳转
   f. build → build_v1_hap → install → 自测（添加供应商→设为默认→测试连接绿字→重启持久）
   g. commit feat(p23b): llm hub
3. **收尾**：DEVPLAN.md 追加 P23 节（含 jtbd-agent 调查弹窗、agent-command 命令面板两项记录为后续可选）→ commit docs(p23)
4. 删除本断点文件或改标 DONE

## 五、已踩坑提示（本仓铁则）
- 全库 CRLF；edit_file 多行匹配必败——**一律 node 补丁脚本**（readFileSync→归一 \r\n 处理→writeFileSync，参考 .verify/p19_patch_*.cjs 命名风格，脚本放 .verify/p23_*.cjs）
- 同文件多 edit 并行=竞态覆盖，必串行
- ArkTS 严格：禁止无类型对象字面量（interface/class 先行）；Record 字面量也禁——LLMClient 里有显式类模式照抄
- ForEach 第三参 key generator 必给（防重渲染异常）
- 改码后必须先 build 再 repack 再装机验证
- quit 时 clearInterval：EntryAbility onDestroy 目前只有 MCPServer.stop——ScheduleManager.stop() 可不加（进程死定时器随之亡），但加上更干净
- vm hdc 127.0.0.1:15566；构建慢（~3min），55 分钟限时内 A 优先于 B

## 六、自测脚本模式（照 .verify/p21_e2e.cjs）
- hdc shell uitest dumpLayout 抓布局 JSON 断言文本存在
- hdc shell aa start -b com.oneaiterm.terminal ...（bundle 见 AppScope/app.json5，P23 不改名）
- hilog 过滤 ScheduleManager/LLMHub 关键字
