# 架构文档 — BrowserOS KaihongOS

> 配套 [DEVPLAN.md](../DEVPLAN.md)（逐阶段台账与设备证据）。本文给出现行代码的静态结构与关键链路。

## 总体形态

单 HAP（`entry` 模块）ArkTS 应用，bundleName `com.browseros.kaihong`。单 Ability + 多 Page 路由，浏览器壳 `BrowserShell` 常驻，功能页经 `router` 推入。Web 内容由 ArkWeb `Web` 组件承载（每个网页标签一个控制器实例，由 `TabManager` 管理生命周期）。

```
┌ BrowserShell（主壳）────────────────────────────────┐
│ Row                                                  │
│ ├ TabStrip(竖排标签条, 200vp)                        │
│ └ 主区 Column                                        │
│   ├ AddressBar（9 引擎/星标/菜单）                    │
│   ├ Row { SidebarRail(14↔64vp hover)                  │
│   │       内容区 { Web | NeoDashboardPanel(新标签页) } │
│   │       [AgentSidePanel(360vp, 停靠聊天/历史)] }     │
│   └ BookmarkBar                                      │
└──────────────────────────────────────────────────────┘
```

## 模块职责（entry/src/main/ets）

| 层 | 文件 | 职责 |
|---|---|---|
| 页面 | `pages/BrowserShell.ets` | 主壳：标签切换、地址栏、侧栏、仪表盘/网页互斥、冷启动 dashboard 优先、主题锚点（`@Watch`+`themeVersion` 规避 @Builder 不重渲染） |
| | `pages/BookmarksPage.ets` | 书签列表/搜索/编辑/删除 + **HTML 导入**（P32） |
| | `pages/HistoryPage.ets` `DownloadsPage.ets` | 历史（搜索/回放入口）、下载（进度/重试/取消） |
| | `pages/LlmHubPage.ets` | 多供应商 LLM 接入（端点/Key/模型） |
| | `pages/ScheduledTasksPage.ets` | 定时任务管理 |
| | `pages/SessionPlayerPage.ets` | 会话回放（回放/时间线/标签页 TabView） |
| | `pages/SettingsPage.ets` | 外观（语言切换顶部卡）/搜索引擎/清除数据/安全等 |
| | `pages/OnboardingPage.ets` `ViewSourcePage.ets` | 首启引导、查看源码 |
| | `pages/PasswordsPage.ets`（P47） | 密码管理器：凭据列表/搜索/自动填充管理（Bitwarden 兼容导入） |
| | `pages/DevToolsPage.ets`（P47） | DevTools Console：console 日志流 + 网络请求记录 |
| | `pages/AuditPage.ets`（P54） | 审计事件查看：时间线/来源（agent/MCP）/脱敏详情 |
| | `pages/ImportWizardPage.ets`（P53） | 登录态导入向导：分步引导 + Profile 隔离 |
| 组件 | `components/TabStrip.ets` | 竖排标签（favicon+标题+关闭钮，`HitTestMode.Default` 保证子按钮收点；`@Prop` 装饰保证父更新触发重渲染——P45 根因修复；折叠 24vp/拖宽 120-400vp——P51） |
| | `components/SidebarRail.ets` | 收起 14vp→hover 展开 64vp（200ms EaseInOut），5 导航项（i18n 经 key 传参内部求值规避 @Builder 缓存——P51） |
| | `components/AgentSidePanel.ets` | 聊天/历史双视图、起手提示词（可自定义+持久化）、运行态停止钮 |
| | `components/NeoDashboardPanel.ets` | Cockpit 仪表盘：hero+聊天输入+磁贴+MCP 安装板（5 框架+46 连接器）+LLM 设置+代理创建+Connect 对话框（fport 命令块+Test 真实握手判定——P52） |
| | `BookmarkBar` `ChromeWidgets` `ConfirmDialog` `ContextMenu` | 配套 UI |
| 服务 | `service/AgentEngine.ets` | 15 步代理循环、SSE 流式（chatStream+回退）、finalAnswers、发光遮罩启停；事件经 AuditEventBus 汇聚（P54） |
| | `service/MCPServer.ets` + `McpJsonRpcCore` + `WsMcpTransport` + `HttpMcpTransport` | 设备端 MCP：WS :8765 + HTTP，JSON-RPC 2.0，密钥校验，**17 工具注册表**（P43），协议 2026-07-28 协商（P52），限流 30req/10s/连接（P43b） |
| | `service/McpSessionStore.ets`（P51） | MCP 会话隔离：session-id 校验、tab ownership、并发隔离（双会话互不串台） |
| | `service/McpEndpointConfig.ets`（P52） | 统一 endpoint 单一真值源：`/mcp` 路径 + hdc fport 命令生成（面板/Connect/harness 配置同源） |
| | `service/HarnessAdapters.ets`（P52） | Claude Code / Codex / Cursor / Generic 四种 harness 的 per-CLI 配置形状生成 |
| | `service/AuditEventBus.ets`（P54） | 统一审计事件总线：内部 agent + 外部 MCP 工具调用同源汇聚 → AuditPage |
| | `service/AuditRedactor.ets`（P51） | 审计输出系统级脱敏（token/key/敏感 URL 参数遮蔽） |
| | `service/TabGroupManager.ets`（P55） | 标签组管理：创建/列取/清理（上游 tab-group cleanup 语义） |
| | `service/CredentialStore.ets`（P47→P51） | 凭据主真值源：Asset Store 硬件加密（P51 迁移完成）；密码管理器+登录态导入共用 |
| | `service/DevToolsCollector.ets`（P47） | console 日志采集（onConsole）+ 网络请求记录（onInterceptRequest）→ DevToolsPage |
| | `service/LLMClient.ets` | OpenAI 兼容调用（云端或 Ollama 兼容端点） |
| | `service/TabManager` `BookmarkManager` `HistoryManager` `DownloadManager` `ScheduleManager` `SessionManager` `ConnectionManager`（P52 重构：connect=config-ready/testConnection=真实握手）`LoginStateManager` `SensitiveOperationDetector` | 领域管理器 |
| 协议 | `protocol/BCPEngine` `JSBridgeInjector`（html2canvas 本地 rawfile 化——P42）`ScreenshotCapture`（tab 定向——P54）`SnapshotGenerator`（Stable SnapshotRef——P55）`WebViewAdapter` | 页面侧操作协议、JS 注入、截图、Markdown 快照、WebView 适配 |
| 存储 | `storage/StorageManager`（文件 JSON）、`PrefsStore`（Preferences）、`HistoryDb`（RDB）、`ConfigManager`、`AuditLogger`、`SecureStorageAdapter`（Asset Store Kit） | 持久层 |
| 基础 | `infra/EventBus`（BOOKMARKS_CHANGED 等跨页广播）、`ErrorHandler`、`PerformanceMonitor`；`common/Palette`（深/浅主题令牌）、`common/I18n`（zh/en 510 条语言包——P48/P49）、`SearchEngines`（9 引擎）、`Constants` | 横切 |

`docmanagement/` 为独立的文档管理套件（ADR/变更/开发日志/会议纪要/状态报告），与浏览器功能解耦。

## 关键链路

- **构建链（API 23 主链）**：`hvigorw assembleHap`（SDK26 产物）→ `tools/build_api23_hap.py`（module.json/pack.info 改 min/target=23 + **ZIP_STORED 重打包**——KaihongOS 6.x zip 读取器只认 STORED 条目，P40 根因）→ 宿主推 VM + 设备端 hap-sign-tool 签名（`tools/install_p56.py` 模式）→ `bm install -r` + `aa start`。
- **构建链（API 14 旧链，存档）**：`tools/build_v1_hap.py`（restool 5.0.1.0.11 重打包 V1 resources.index，绕过 API14 不识别 RestoolV2）→ `tools/install_p8.py` → `tools/add_desktop_shortcut.py`。`tools/deploy.py` 串联全链。
- **Agent 链**：输入（侧栏/新标签页/定时）→ AgentEngine 循环 → LLMClient 调用 → 流式回填 UI → 操作经 BCPEngine/JSBridge 注入页面执行 → 快照回评；全程事件入 AuditEventBus（P54）。
- **MCP 链**：外部/本机客户端 → 统一 endpoint `/mcp`（McpEndpointConfig 真值源，P52）→ Http/Ws 传输（token 鉴权 → McpRateLimiter 限流 → McpSessionStore 会话隔离，P51）→ McpJsonRpcCore 分发（协议 2026-07-28 协商）→ 17 工具注册表执行 → 审计入 AuditEventBus。
- **Harness 接入链（P52）**：NeoDashboardPanel Connect 对话框 → HarnessAdapters 生成 per-CLI 配置 → 用户在 harness 侧执行 fport 命令 → testConnection() 真实 initialize 握手 → harness_connected_<name> 持久化。
- **凭据链（P47→P51）**：密码管理器/登录态导入 → CredentialStore → Asset Store 硬件加密（主真值源）；config.json 恒脱敏。
- **审计链（P54）**：AgentEngine（内部）+ MCPServer 工具调用（外部）→ AuditEventBus → AuditRedactor 脱敏 → AuditPage 展示 + AuditLogger 落盘。
- **主题链**：SettingsPage 写 AppStorage('darkMode') → 各页 `@StorageProp` + BrowserShell `@Watch('onThemeFlip')` 递增 `themeVersion` 驱动 @Builder 重渲染（P44 扩展至全部 18 页/组件）。
- **i18n 链（P48-P51）**：SettingsPage 语言 pill → I18n.setLocale → localeVersion 递增（渲染锚）→ 各组件重求值（@Builder 传 key 不传译文，规避值参数缓存）。
- **书签导入链（P32）**：BookmarksPage「导入」→ DocumentViewPicker 选 html → fs 读取 + TextDecoder 解码 → Netscape `<A HREF>` 正则解析 → BookmarkManager.importBookmarks（url 去重、单次持久化、EventBus 广播）。

## 平台约束备忘

- 明文 HTTP 禁用（瞬断）——MCP HTTP 走本机回环例外。
- `OnDownloadStartEvent` 无 suggestedFileName（API14 d.ts 实测），下载名从 URL 兜底推导。
- TextInput 回灌缺陷：编辑态避免程序化回写 text。
- ArkUI `layoutWeight` 嵌套挤压需沿根链直挂（SessionPlayer 时间线页实测）。

## 测试

- 设备在环：`tools/smoke_reg.py` 9 步（设备/安装/冷启动/渲染/静态 a11y/MCP HTTP/书签入口/屏注册/图标像素门禁）。
- 离线静态：`tools/static_checks.py`（py_compile 全量、console.log 禁用、$rawfile 图标规范、清单完整性、合规文件在场、图标集下限）——CI 同款。
- MCP 互操作门禁：`tools/mcp_client_e2e.py` 15 项（initialize/tools/list 17/全链/负例/限流）。
- Harness 互操作：`tools/harness_compat_test.py`（6 harness × initialize+tools/list+call 链，41 项）。
- 性能：`tools/perf_probe.py`（冷启动/PSS 采样，基线见 docs/PERFORMANCE.md）。
- 证据库：`evidence/p1..p56`、`evidence/r1..r11`。
