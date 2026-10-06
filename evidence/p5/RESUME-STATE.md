# P5 RESUME STATE（2026-10-06 15:25 收棒固化）

## 本棒已完成并装机验证（build 15:01 + repack + 装机）

### 1. Agent tab 渲染修复 ✅ 已实证
**真根因不是 ForEach/事件链，是布局**：tab item 的 Text 有 `layoutWeight(1)` 而外层 Row 没有——第一个 tab 的 Text 把后续 tab 挤成 4px 宽（布局 dump 实锤 `Row [1371,235][1375,262]`），ForEach 一直正常渲染只是不可见。
**修复**：BrowserShell.ets tab item Row 加 `.layoutWeight(1)`（.verify/p5_patch_lw.cjs）。
**实证**（uitest dumpLayout）：
- 3 标签并存：`about:blank [503,276][823,288]` + `Dashboard [849,276][1158,288]` + `Agent f8bhw5 [1195,276][1504,288]`（等分宽 ~310px）
- 点「+」新建标签立即出现第二个 tab ✅
- agent 创建后标签栏出现「Agent f8bhw5」标题 tab ✅（标题=代理名）

### 2. Agent tab 激活挂 Web ✅ 已实证
点 agent tab 后 hilog：
```
BrowserShell created WebviewController for tabId=tab_3_1791270985416
BrowserShell onControllerAttached tabId=tab_3_1791270985416
BrowserShell registered webview adapter for tabId=tab_3_1791270985416
BrowserShell onPageEnd tabId=tab_3 url=about:blank
```
布局 dump 同时出现 `Web | about:blank` 组件 ✅

### 3. 附带部署的补丁（本棒 4 个 node patch，全在 .verify/p5_patch_*.cjs）
- covering 标记（onPageHide/onPageShow 维护）
- tabsDirty 两帧重建（setTimeout 0 清空→重建，日志 "rebuild tabs next frame: 2" 确认执行）
- 这些是对覆盖态同步的加固，与 layoutWeight 主修复共存无害

### 4. B7 书签/历史 UI 已在（前棒）：工具栏 ☆/🕘 按钮 + 「书签 0 条 · 历史 0 条」
### 5. ConfirmDialog 已挂 BrowserShell build()（代码确认）

## ⚠️ 遗留缺口（下棒第一优先）
**BCP 工具链对活 agent 的端到端验证未完成**：
- 时序竞态：agent 在 NeoDashboard 页创建并立即开跑（15:16），而用户点回 agent tab 是 15:18——agent 已跑完（15:17:16 task complete），期间所有 BCP 调用报 "Init error. The WebviewController must be associated with a Web component"
- **待验证**：agent 存活期间（15 步循环约 40s）点 agent tab → registerWebView 后 BCP navigate/getText/screenshot 是否转为成功 → sessions/*.json screenshots>0 → answer 含 Example Domain
- e2e 卡点：窗口在 VM 重启间漂移（BrowserShell 从左侧 304 挪到右侧 494+），坐标脚本频繁失焦；「查看代理」按钮点击偶发不生效（需点后 dump 确认进入了 NeoDashboard 再填表）

## e2e 工具链（全在 .verify/，用法）
- `p5_e2e.cjs dump|inputs|clickxy x y|type "text"|sleep ms`（type 是 uinput -K 键盘文本）
- `p5_tabband2.cjs`：tab 栏带状布局 dump（y 264-302）
- `p5_chain.cjs`：BCP/AgentEngine/WebView 链路日志
- `p5_grep.cjs "kw"`：JSAPP 日志 grep
- 装机：`hvigorw assembleHap → python .verify\p5_repack.py → node .verify\p5_deploy.cjs`（先 build 再 repack 铁则）

## NeoDashboard 表单坐标（窗口在左半时）
名称(840,365) URL(840,402) 任务(840,440) 创建(840,481)；查看代理(840,374)——**先 dump 再点**，窗口漂移后坐标全变
