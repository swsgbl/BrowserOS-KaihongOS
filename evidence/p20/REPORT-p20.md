# P20 验收报告 — R9 审计三缺口（无障碍标注 / 书签搜索 / 回归脚本化）

日期: 2026-10-10 | 基线: 0230aef → 三笔 commit 1f46052 / e4b19ae / (p20c)

## A. 无障碍标注 (p20a, commit 1f46052)
**改动**: 图标-only 可点控件补 `accessibilityText` 共 20 处（跳过已有可见文字的按钮）：
- BrowserShell 工具栏 11 处: 后退/前进/刷新或停止(随 isLoading 切换)/加书签或编辑(随 isBookmarked)/历史/主页/Agent 侧栏/主菜单/查找上一个/查找下一个/错误条关闭
- TabStrip 4 处: 标签关闭(含标签标题动态朗读)/新建标签页/搜索标签页/面板标签关闭
- BookmarkBar 2 处: 书签 pill(朗读名或 URL)/全部书签入口
- AgentSidePanel 关闭 1 处; Bookmarks/History 页返回箭头 2 处
**验证**: 构建通过 + 装机启动无崩溃。**限制**: QEMU 的 `uitest dumpLayout` 通道 descriptions 全空（平台不透出 a11y 文本），运行时朗读验证需真机读屏；已通过装机后行为回归（导航/标签/书签路径全部正常）确认无副作用。

## B. 书签页搜索 (p20b, commit e4b19ae)
**改动**: BookmarksPage 顶栏下新增搜索行（ic_search + TextInput placeholder=搜索书签 + 清除钮），`filtered()` 大小写不敏感匹配 title/url，计数随过滤实时变化，无命中显示「无匹配书签」空态。
**E2E 验证（VM 在线时实测）**:
- BookmarkBar「全部书签」入口 → 书签页: **PASS**（dump 见 placeholder）
- 输入 `bro` → 可见行 0 + 计数 `0 条` + 空态: **PASS**（书签库无含 bro 项，过滤逻辑生效）
- 输入 `zzzz` → 「无匹配书签」: **PASS**

## C. 冒烟回归脚本 (p20c)
**改动**: `tools/smoke_reg.py`（无三方依赖）7 步检查链：
1. hdc 目标在线（tconn+list）
2. bundle 已安装（bm dump）
3. 冷启动（force-stop → aa start → hilog 断言 EntryAbility onCreate/onForeground）
4. 前台渲染（dumpLayout 含 BrowserOS 标题+TextInput）
5. a11y 静态计数（源码 accessibilityText ≥ 20）
6. MCP HTTP initialize（读 mcp_token.txt → fport 9222 → POST initialize 断言 serverInfo）
7. 书签页搜索框（布局定位全部书签入口 → uinput -T -c 点击 → dump 断言 placeholder）
输出 PASS/FAIL 表 + 退出码 0/1。
**验证**: 设备离线时正确 FAIL 并 exit 1（行为已验证）。**注**: 本机 QEMU 二进制（C:\Program Files\qemu）在任务中途丢失、VM 无法重启，在线全链跑批留待 VM 恢复后执行 `python tools/smoke_reg.py`。

## 关键坑（本轮新增）
1. **uinput 点击必须用 `-T -c x y`**（click），`-T -g x y x y ms ms`（gesture）在 KaihongOS 上不触发 onClick——本轮 5 次点击全部无效的根因，p5 时代的 e2e 脚本用的就是 -c。
2. uitest dumpLayout 不含 accessibilityText/description（全空）——a11y 运行时验证需其他通道（真机读屏/无障碍服务）。
3. QEMU 安装路径 C:\Program Files\qemu 被外部清空（old-launchers 同样指向该路径），VM 链路断；hdc "need connect-key" = 目标掉线。
4. 装机自测时 uniterm(tty7)/terminal0 窗口会抢焦点，dump 前先 `aa start` 拉回。

## 环境备注
- hdc 目标 127.0.0.1:15566（KaihongOS QEMU，任务中断连）; bundle com.browseros.kaihong
- 构建: hvigorw assembleHap → tools/build_v1_hap.py → tools/install_p8.py（本轮全链走通，装机+启动+启动验证 PASS）
- MCP: HTTP 9222(/mcp?token=) / WS 8765, token 文件 haps/entry/files/mcp_token.txt
