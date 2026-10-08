# P11 断点(RELAY2,2026-10-08 Phase A 完成,上下文耗尽)

git 基点 be794e6 = feat(p11a) 已 commit。Phase B(标签条形状)/C(右键菜单)/D(书签条)/E(收尾)未动。

## 本棒完成(Phase A 全部)
1. 28 枚 ic_*.svg(Material 24x24 path,无 fill 属性,fillColor 染色)写入 entry/src/main/resources/base/media/
2. BrowserShell.ets AddressBar 9 按钮(←/→/↻/🔒ⓘ/☆★/🕘/⌂/❐/⋮)全换 Image($r)+fillColor
3. TabBar 内联区:favicon 方块→ic_globe/ic_robot 染色、×→ic_close、+→ic_add、●状态点已删
4. ChromeWidgets.ets:ThreeDotMenu MenuEntry.icon 改 Resource 类型(8菜单项+退出全 SVG)、OmniboxSuggestions 行图标 SVG
5. 装机验证通过:工具栏图标全部矢量形状渲染(p11a-icons2.jpeg 实证,vision 模型确认 ←/→/⟳/🏠/🕘/⋮ 可辨)

## 本棒踩坑(下棒必读)
- **同文件多 edit 并行=竞态覆盖**:6 笔并行 edit_file 同一 .ets 只有最后 1 笔落盘,前 5 笔丢失。**同文件多处编辑必须串行!**
- **V1 repack 链新增 SVG 必须三步**:①复制 svg 到 D:\v1tmp\final\resources\base\media\ ②tools/p11_add_svgs_v1.py 增补 final_ids.json(28条,复用 hvigor id_defined.json 的 ID) ③再跑 build_v1_hap.py。否则 $r() 运行时解析失败→图标渲染为蓝色方块(p11a-toolbar.jpeg 是反面证据)
- **新增 media 资源后 restool 只报 4 个 png OK 是正常的**(它核对的是 hvigor hap 内的 png,svg 在 V1 输入目录单独喂)
- vision see_image 偶发空回复,重试或换简短英文 prompt
- 设备截图若显示桌面=截在启动动画,重截即可(mission created 日志可佐证已启动)
- findstr \| 管道在 cmd 下诡异失败,用 node -e 读文件验证字符串

## 下棒执行序(照 RESUME-STATE-RELAY1.md Phase B-E 细节 + 本文件增量)
Phase B:内联 TabBar Chromium 化——active tab 形状(内容区同色 pal.surface+上圆角8+条底 pal.surfaceAlt)、inactive 半透明(hover 亮)、TabSearchPanel 组件(ic_tab_search 需补 1 枚 SVG:圆+下拉箭头)、× hover 态。红线:tab Row .layoutWeight(1) 保留。
Phase C:components/ContextMenu.ets 通用菜单(白/深卡+圆角8+阴影+行 icon18+文字13+快捷键11+hover#F0F1F3+分隔线+宽240)+ Web.onContextMenuShow(行6650 回调return true 自绘;param.x()/y()/getLinkUrl())页面右键(后退/前进/刷新/加书签/复制网址/查看源码)+ tab 右键(新建/关闭/关闭其他/关闭右侧——TabManager 无 closedTabs 栈,"重新打开已关闭"置灰)+ ViewSourcePage.ets(runJavaScript document.documentElement.outerHTML)+ main_pages.json 注册第8页
Phase D:BookmarkBar(工具栏下 32px,仅 showDashboard/内建页显示;pill 排列 ref1;getAllBookmarks)+ omnibox 下拉分组(首行"搜索 xxx"+历史组+书签组)+ BookmarkBubble 文件夹只读行
Phase E:grep 全部 ets 字形残留清零→evidence/p11 全表面截图→DEVPLAN 追加 P11 节

构建链(每 Phase):harmony_build → python tools/p11_add_svgs_v1.py(若新增svg) → python tools/build_v1_hap.py → python tools/install_p8.py → hdc截图+see_image → git commit feat(p11b/c/d/e)
