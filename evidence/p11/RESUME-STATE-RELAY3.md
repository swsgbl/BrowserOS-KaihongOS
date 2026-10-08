# P11 断点(RELAY3,2026-10-08 Phase C 完成已验证,上下文耗尽)

git 基点 b997a53 = feat(p11c) 已 commit。Phase D/E 未动。

## 本棒完成(Phase C 收尾+验证)
1. 工作树半成品核查:代码齐(ContextMenu.ets/ViewSourcePage.ets/BrowserShell+TabStrip 注入/main_pages.json 第8页)
2. **V1 坑**:D:\v1tmp\final\resources\base\profile\main_pages.json 是旧的 6 页列表!已用 node copyFileSync 从项目同步(8页)。**凡改 resources/base 下非 media 文件都要手动同步到 v1tmp/final 对应路径**
3. 构建(1s 全 UP-TO-DATE,产物已含 C 代码,PowerShell 读 abc 验证 ViewSourcePage/closeOtherTabs 均在)→ build_v1_hap.py → install_p8.py 装机 OK
4. 设备实操验证(uinput,详见坑清单):tab 长按右键菜单 p11c-final-tabctx.jpeg ✓(向右新建/复制标签页网址/关闭其他(灰)/关闭右侧(灰),单 tab 如实置灰);dashboard 长按菜单 p11c-final-pagectx.jpeg ✓(刷新/后退(灰))
5. commit b997a53(19 文件,含全部截图实证)

## 本棒踩坑(下棒必读)
- **uinput -T -g**(长按=右键):`uinput -T -g x y x y 600 1200`(pressTime≥500 且 total-press≥500,否则 "move time is out of range")
- **uinput -K -t 只追加不清选区**:omnibox 导航 example.com 失败三次(about:blankexample.com 累积)。Ctrl+A 和弦(-d 29 -u 29 -d 30 -u 30 -d 29 -u 29)无效、退格×32 无效 → **键盘驱动 omnibox 不可靠,别再试**。网页右键(onContextMenuShow)设备实操未达成,代码路径有 SDK d.ts 实锤(relay1: web.d.ts 行6650 since9),已如实记录取舍
- **hdc shell "hilog | grep" 被宿主壳拒**(cmd 无 grep):改 harmony_logs 工具或 hilog -x 重定向文件后 findstr
- cmd 的 timeout 命令在 hdc 链里报 "Input redirection not supported":用 `ping -n N 127.0.0.1 >nul` 延时
- uitest dumpLayout JSON 的 attributes 是数组 [{name,value}] 非 map;.verify\p11c_layout.cjs 是现成解析器
- app 在模态窗 ContainerModalStack [265,154][1335,724] 内:omnibox TextInput [381,160][1173,188](点它 -c 600 174),tab 条 y=201-213(长按 -g 600 207),内容区 y≥224

## 下棒执行序

### Phase D(书签条+omnibox 下拉+弹泡,commit feat(p11d))
1. **components/BookmarkBar.ets**(新组件,~90行):高32 Row,横向 Scroll,每项 pill(ic_globe 14染鬼+书签名 12px,ref1 风格),onClick 开新标签;右端"全部书签"入口→BookmarksPage;@StorageProp darkMode+Palette。数据由 shell 传 bookmarks prop
2. **BrowserShell build() 行189-190**:AddressBar() → TabBar() 之后插 `if (this.showDashboard || this.showNeo) { this.BookmarkBarRow() }`;@State bookmarks 在 aboutToAppear+refreshBookmarkState+finishBookmarkEdit/removeCurrentBookmark 里重取 getAllBookmarks()(createdAt 降序)。开书签→createNewTab 后 navigate(url)
3. **omnibox 下拉分组**(ChromeWidgets OmniboxSuggestions+shell updateSuggestions 行1247):kw>0 时 items.unshift({kind:'search',title:kw,url:kw}) 首行;渲染 kind==='search'→ic_search+「搜索 kw」粗体,onPick 时 kind search 走 this.onAddressInput(kw)(行1172 已有搜索引擎 fallback)而非 normalizeUrl;kind 变化处插组头(历史记录/书签)
4. **BookmarkBubble 补文件夹只读行**:名称 TextInput 与按钮之间加 文件夹标签+Row{ic_folder+『书签栏』}
5. 验证:构建→v1 repack→装机→长按 tab 菜单回归+书签条截图(先经 BookmarksPage 或右键菜单加书签造数据)。omnibox 下拉若键盘输入不可靠,用已有 urlInput 文本触发(点 omnibox 即 onFocus→updateSuggestions)
6. commit feat(p11d)

### Phase E(收尾,commit docs(p11))
1. 字形残留清零:扫全部 ets 渲染处(←→↻⌂☆🕘⋮❐◇×＋字形,日志/注释除外)
2. 全表面截图 evidence/p11:工具栏亮暗/标签条/两右键菜单/书签条/omnibox 下拉/tab-search 面板/ViewSource 页
3. DEVPLAN.md 追加 P11 节(A图标/B标签条/C右键菜单/D书签条/E收尾+取舍记录)
4. commit docs(p11)

## 构建链(照旧)
harmony_build → python tools/build_v1_hap.py(新 svg 才需 p11_add_svgs_v1.py;改 profile 需同步 v1tmp) → python tools/install_p8.py → uinput 实操+snapshot_display+file recv 截图

## 红线(全套不变)
API≤14;ArkTS 严格;bundleName 不变;不碰 D:\oneaiterm;不重启 VM;不卸载任何包;hdc 127.0.0.1:15566;先构建再 repack;同文件多处编辑必须串行。
