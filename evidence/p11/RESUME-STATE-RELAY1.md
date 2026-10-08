# P11 断点（RELAY1，2026-10-08 侦查完成，代码零写入）

任务书：.zcode/p11_brief.md（Phase A-E：SVG图标体系/Chromium标签条/右键菜单/书签条+omnibox/收尾）
git 基点 5264dcf（P10 已收官）。参考图 ref1-5 已看：BrowserOS 官方 UI=书签条(QQ邮箱/智谱/ChatGPT等 pill 排列)+单tab+左侧设置导航+橙色强调。

## 侦查结论（下棒直接用，勿重复查）

### 1. 图标现状（Phase A 落点）
- BrowserShell.ets (~890行) 文字字形：← → ↻(工具栏3钮) 🔒/ⓘ(omnibox) ☆/★(星标) 🕘(历史) ⌂(home) ❐(侧栏) ⋮(菜单) —— 全在 AddressBar() builder
- TabBar 区(内联在 BrowserShell，非组件)：'A'/'◇' favicon方块、× 关闭、＋ 新建
- ChromeWidgets.ets：ThreeDotMenu(＋⧉🕘★⭳⚙?⏻)、OmniboxSuggestions(★🕘行图标)、BookmarkBubble
- media/ 目录现有：仅 app_icon*.png 5个，无 SVG。新增 ic_*.svg 放 entry/src/main/resources/base/media/
- Image($r('app.media.ic_back')).width(20).height(20).fillColor(...) 可染 SVG

### 2. TabBar.ets 组件是孤儿（71行，BrowserShell 零引用）——内联 TabBar builder 在 BrowserShell，直接改内联版
- 红线：tab item Row 的 .layoutWeight(1) 必须保留（P5 布局挤压教训）；多 Web 常驻架构（WebViewContent 每tab一个Web）不动
- active 标签 Chromium 形状：近似方案=内容区同色+上圆角8px（active= pal.surface，条底= pal.surfaceAlt，同色视觉连通）
- inactive：浅 rgba(0,0,0,0.05)/深 rgba(255,255,255,0.05)，hover 亮（onTouch 或 stateStyles）
- tab-search 面板：新组件 TabSearchPanel（列表 favicon+标题+×，点击切换）——纯前端，数据 this.tabs

### 3. SDK 实锤（本机 API26 SDK web.d.ts，component/web.d.ts 行号）
- **Web.onContextMenuShow 存在，since 9 ≤API14 可用**（行6650）：`onContextMenuShow(callback: Callback<OnContextMenuShowEvent, boolean>)`，**回调 return true=自绘菜单生效**
- OnContextMenuShowEvent(行4701)：{ param: WebContextMenuParam, result: WebContextMenuResult }
- WebContextMenuParam(行2403)：x() y() px坐标、getLinkUrl()、getSelectionText()、getSourceType()、existsImageContents()
- WebContextMenuResult(行2556)：closeContextMenu() 等
- → Phase C 页面右键直接用 onContextMenuShow，无需透明层叠！菜单项：后退/前进/重新加载/添加书签/复制网址/查看源码

### 4. 服务层 API 现状
- BookmarkManager：addBookmark(url,title)/removeBookmark(id)/updateBookmark(id,url?,title?)/getAllBookmarks()(createdAt降序)/searchBookmarks(kw)/isBookmarked(url)/getBookmarkIdByUrl(url)/getBookmark(id)/getBookmarkCount()
- TabManager：createTab/createAgentTab/switchTab/closeTab/getAllTabs/getActiveTabId/updateTabUrl/updateTabTitle —— **无 closedTabs 栈**（"重新打开已关闭标签"如实置灰或 BrowserShell 内存自记）、**无 closeOthers/closeRight**（BrowserShell 遍历实现）
- main_pages.json 现有 7 页，ViewSourcePage 需注册第 8 页

### 5. 构建链（照抄 p9r/p10）
harmony_build(或 hvigorw assembleHap) → tools/build_v1_hap.py(V1 repack，**改码后必须先构建再 repack**) → tools/install_p8.py(VM 15566 hap-sign-tool browseros-profile-release.p7b 签名+bm install -r+aa start)
hdc：127.0.0.1:15566（hdc.exe 在 C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe）
截图验证：hdc shell snapshot_display -f /data/local/tmp/v.jpeg && hdc file recv（recv 用反斜杠路径）

## 执行顺序
1. Phase A：写 25 枚 ic_*.svg（Material 风格 24x24 stroke path）→ 替换 BrowserShell 工具栏+TabBar+ChromeWidgets 全部字形 → 构建→装机→commit feat(p11a)
2. Phase B：内联 TabBar Chromium 化（active形状/inactive半透明/favicon ic_globe/ic_robot/×hover/ic_plus/ic_tab_search+TabSearchPanel）→ commit feat(p11b)
3. Phase C：新 components/ContextMenu.ets（通用：白/深卡+圆角8+阴影+行 icon18+文字13+灰快捷键11+hover#F0F1F3+分隔线+宽240）+ Web.onContextMenuShow(return true)+标签右键+ViewSourcePage(runJavaScript 取 document.title+body.innerText) → commit feat(p11c)
4. Phase D：BookmarkBar（工具栏下32px，仅 dashboard/内建页显示）+ omnibox 下拉分组（首行"搜索 xxx"+历史/书签组）+ BookmarkBubble 加文件夹只读行 → commit feat(p11d)
5. Phase E：grep 字形残留清零 → 全表面截图存 evidence/p11/ → DEVPLAN 追加 P11 节 → docs(p11)

## 红线（不变）
API≤14；bundleName 不变 com.browseros.kaihong；不碰 D:\oneaiterm；不重启 VM；不卸载任何包；tab layoutWeight 链勿断；多 Web 常驻勿动；每 Phase 构建+装机+commit。
