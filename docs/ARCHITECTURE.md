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
| | `pages/SettingsPage.ets` | 外观/搜索引擎/清除数据/安全等 |
| | `pages/OnboardingPage.ets` `ViewSourcePage.ets` | 首启引导、查看源码 |
| 组件 | `components/TabStrip.ets` | 竖排标签（favicon+标题+关闭钮，`HitTestMode.Default` 保证子按钮收点） |
| | `components/SidebarRail.ets` | 收起 14vp→hover 展开 64vp（200ms EaseInOut），5 导航项 |
| | `components/AgentSidePanel.ets` | 聊天/历史双视图、起手提示词（可自定义+持久化）、运行态停止钮 |
| | `components/NeoDashboardPanel.ets` | Cockpit 仪表盘：hero+聊天输入+磁贴+MCP 安装板（5 框架+46 连接器）+LLM 设置+代理创建 |
| | `BookmarkBar` `ChromeWidgets` `ConfirmDialog` `ContextMenu` | 配套 UI |
| 服务 | `service/AgentEngine.ets` | 15 步代理循环、SSE 流式（chatStream+回退）、finalAnswers、发光遮罩启停 |
| | `service/MCPServer.ets` + `McpJsonRpcCore` + `WsMcpTransport` + `HttpMcpTransport` | 设备端 MCP：WS :8765 + HTTP，JSON-RPC 2.0，密钥校验，10 工具注册表 |
| | `service/LLMClient.ets` | OpenAI 兼容调用（云端或 Ollama 兼容端点） |
| | `service/TabManager` `BookmarkManager` `HistoryManager` `DownloadManager` `ScheduleManager` `SessionManager` `ConnectionManager` `LoginStateManager` `SensitiveOperationDetector` | 领域管理器 |
| 协议 | `protocol/BCPEngine` `JSBridgeInjector` `ScreenshotCapture` `SnapshotGenerator` `WebViewAdapter` | 页面侧操作协议、JS 注入、截图、Markdown 快照、WebView 适配 |
| 存储 | `storage/StorageManager`（文件 JSON）、`PrefsStore`（Preferences）、`HistoryDb`（RDB）、`ConfigManager`、`AuditLogger`、`SecureStorageAdapter` | 持久层 |
| 基础 | `infra/EventBus`（BOOKMARKS_CHANGED 等跨页广播）、`ErrorHandler`、`PerformanceMonitor`；`common/Palette`（深/浅主题令牌）、`SearchEngines`（9 引擎）、`Constants` | 横切 |

`docmanagement/` 为独立的文档管理套件（ADR/变更/开发日志/会议纪要/状态报告），与浏览器功能解耦。

## 关键链路

- **构建链**：`hvigorw assembleHap`（SDK26 产物）→ `tools/build_v1_hap.py`（restool 5.0.1.0.11 重打包 V1 resources.index，绕过 API14 不识别 RestoolV2）→ `tools/install_p8.py`（hdc 推送 + 设备端 hap-sign-tool 签名安装）→ 启动 → `tools/add_desktop_shortcut.py`（launcher DB/描述符原子替换）。`tools/deploy.py` 串联全链。
- **Agent 链**：输入（侧栏/新标签页/定时）→ AgentEngine 循环 → LLMClient 调用 → 流式回填 UI → 操作经 BCPEngine/JSBridge 注入页面执行 → 快照回评。
- **MCP 链**：外部/本机客户端 → WS:8765（密钥握手）或 HTTP → McpJsonRpcCore 分发 → 工具注册表执行。
- **主题链**：SettingsPage 写 AppStorage('darkMode') → 各页 `@StorageProp` + BrowserShell `@Watch('onThemeFlip')` 递增 `themeVersion` 驱动 @Builder 重渲染。
- **书签导入链（P32）**：BookmarksPage「导入」→ DocumentViewPicker 选 html → fs 读取 + TextDecoder 解码 → Netscape `<A HREF>` 正则解析 → BookmarkManager.importBookmarks（url 去重、单次持久化、EventBus 广播）。

## 平台约束备忘

- 明文 HTTP 禁用（瞬断）——MCP HTTP 走本机回环例外。
- `OnDownloadStartEvent` 无 suggestedFileName（API14 d.ts 实测），下载名从 URL 兜底推导。
- TextInput 回灌缺陷：编辑态避免程序化回写 text。
- ArkUI `layoutWeight` 嵌套挤压需沿根链直挂（SessionPlayer 时间线页实测）。

## 测试

- 设备在环：`tools/smoke_reg.py` 7 步（设备/安装/冷启动/渲染/静态 a11y/MCP HTTP/书签入口）。
- 离线静态：`tools/static_checks.py`（语法编译、console.log 禁用、清单完整性、关键文件在场）。
- 证据库：`evidence/p1..p31`、`evidence/r1..r11`。
