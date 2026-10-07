# P9 断点（relay1 侦查完毕，代码未写——上下文耗尽，下棒直接开工）

任务书：.zcode/p9_brief.md（A chrome补全 / B Agent侧栏 / C 内建页 / D 视觉）。DEVPLAN P1-P8 已收官。
阶段序：A→B→C1→C2→C3/C4→D，每 Phase 构建+装机+自测+`feat(p9x):` commit。

## 已核实的代码事实（下棒免重读）

### BrowserShell.ets（819行，entry/src/main/ets/pages/）
- 结构：`@Entry struct BrowserShell`；build = Column{ AddressBar / TabBar / Stack{WebViewContent, DashboardContent(showDashboard), NeoDashboardPanel(showNeo)} , HistoryPanel(showHistory), ConfirmDialog }
- 关键@State：currentUrl/urlInput/tabs/activeTabId/isLoading/loadProgress/isBookmarked/showHistory/showNeo/historyItems/showImportPanel/importPath/importResult/showDashboard
- 私有：controllers Map(tabId→WebviewController)、pendingUrl/pendingUrlTab、tabsDirty/covering、attachedTabs
- 方法：aboutToAppear/onPageShow(covering=false+syncFromTabManager)/onPageHide/syncFromTabManager(两帧重建)/onTabStatusChange/refreshBookmarkState/toggleBookmark/importLoginState/doImport/openHistory/goHome/getOrCreateController/registerController(WebViewAdapter→TabManager.registerWebView+BCPEngine.bindWebView)/getActiveController/getControllerFor/onAddressInput/normalizeUrl(navigate前缀https)/navigate(pendingUrl机制)/isUrl(已支持端口)
- AddressBar Builder：←/→/↻ 三个36px Button + TextInput(layoutWeight1) + 进度% + ☆/🕘/⌂ —— **无安全锁、无建议下拉、无 ⋮ 菜单**（P9-A 全部要新增）
- TabBar Builder：ForEach(tabs,keyGenerator=tabId) tab项=Row{Text(title兜底'代理'+agentId前12)+●+×} .layoutWeight(1)（P5修复保留！）+ 右侧 + 按钮。**无favicon占位、当前标签非白底上圆角**（P9-A4 改造点）
- WebViewContent：ForEach 每 tab 常驻 Web({src:'about:blank',controller:getOrCreateController}) visibility(active&&!showDashboard) ；onControllerAttached→registerController+pendingUrl补载；onPageEnd→HistoryManager.recordNavigation+TabManager.updateTabUrl/Title+敏感检测+JSBridge注入
- P6红线：多Web常驻架构勿动；tab item 的 .layoutWeight(1) 勿删（P5布局挤压修复）

### 可复用服务接口（已验签名）
- TabManager: createTab(isDashboard=false)/createAgentTab(agentId)/switchTab/closeTab/getTab/getAllTabs/getActiveTabId/updateTabUrl/updateTabTitle/updateTabStatus/registerWebView/getWebView
- BookmarkManager: addBookmark(url,title):Bookmark{id,url,title,createdAt}/removeBookmark(id)/updateBookmark(id,url?,title?)/getAllBookmarks()/searchBookmarks(kw)/isBookmarked(url)/getBookmarkIdByUrl(url)/getBookmarkCount() —— Bookmark 是 interface(非export，页面用 duck-typing 或在该文件 export)
- HistoryManager: getAllHistory(limit):HistoryEntry{url,title,timestamp,...}(export interface)/recordNavigation
- AgentEngine: createAgent(name,targetUrl,taskDescription,RunStrategy.ONCE)→创建即自动开跑(P2)；getAllAgentStatus():AgentStatusInfo[]/getAgentConfig/getSessionId(agentId)/terminateAgent —— **无独立"发消息"API**，侧栏任务=调 createAgent
- ConfigManager: get()/update(AppConfigUpdate)/getLlmBaseUrl/getLlmApiKey/getLlmModel/isLlmConfigured/getMcpPort/getAuthToken在MCPServer
- MCPServer: isRunning()/getPort()/getAuthToken() —— C1 设置页 MCP 节用
- SessionManager.getSessionList():SessionRecord{sessionId,agentId,operationLogs,screenshots,startTime,endTime}；回放=router.pushUrl('pages/SessionPlayerPage',{sessionId})
- NeoDashboardPanel(export struct)已含：MCP端点拼装 getMcpEndpoint()/buildHarnessJson(harness)/copyToClipboard(pasteboard)/LLM表单+创建代理表单/agent磁贴+回放按钮 —— B/C1 复用其逻辑模式

### main_pages.json 现有6页
TestPage/BrowserShell/DashboardPage/SessionPlayerPage/OnboardingPage/NeoDashboardPage。新页：SettingsPage/HistoryPage/BookmarksPage/DownloadsPage 需注册。

## 参考图侦查结论
ref1=Edge风浏览器+左侧BrowserOS竖栏（"What should your agent work on next?"+橙色强调）；ref2=设置页左导航（AI & Agents 选中橙描边/Other组/HELP组底部）；ref3视觉模型空返（按任务书文字规格执行：标签条+Agent下拉+网格）；ref4实为 BrowserOS as MCP 设置页（Connected agents 圆角卡列表样式可借鉴历史页）。任务书规格优先于图片。

## 构建装机链（DEVPLAN 杈权威，勿改）
tools/build_v1_hap.py → tools/install_p8.py → tools/add_desktop_shortcut.py；hdc 127.0.0.1:15566；bundleName com.browseros.kaihong 不变；API≤14；不重启VM/不卸载包/不碰D:\oneaiterm与5555。**注意：改码后必须先构建再repack（P4教训）**。

## 下棒执行清单
1. Phase A：BrowserShell 加 ⋮ 菜单(自绘下拉：新建标签页/新窗口|历史|书签|下载|设置|帮助|退出)+omnibox安全锁+聚焦建议下拉(历史+书签匹配)+星标Bookmark气泡(名称编辑+完成/删除)+图标统一20vp #5F6368+标签条favicon方块/白底上圆角 — 构建装机 commit feat(p9a)
2. Phase B：工具栏侧栏切换按钮+AgentSidePanel组件(360vp，标题Agent+模型下拉+⚙、消息气泡列表、底部输入+发送；发送=AgentEngine.createAgent(task=input)) — commit feat(p9b)
3. Phase C1 SettingsPage(router注册)：左240导航(AI与Agent/外观/隐私与安全/MCP/关于)+右卡片；LLM表单迁移自NeoDashboardPanel.AgentSetupCard模式；MCP节复用getMcpEndpoint — commit feat(p9c1)
4. C2 HistoryPage(搜索+日期分组+agent会话▶回放) C3 BookmarksPage C4 DownloadsPage(空态) C5 新窗口(退化为新建tab,如实记录) — commit feat(p9c2)
5. Phase D：全局色板(#F1F3F4 chrome/#FFF内容/#5F6368/#1A73E8/卡8-12px圆角/分隔#E0E0E0)+omnibox识别 browseros://settings 等内建scheme — commit feat(p9d)
6. 收尾：build_v1_hap→install_p8→add_desktop_shortcut→截图(菜单展开/侧栏/设置/历史/书签/下载)存evidence/p9/→DEVPLAN追加P9节→git提交
