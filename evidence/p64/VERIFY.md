# P64 验证报告：测试基建健壮化——smoke 双模式 9/9 + 20 项回归矩阵

日期: 2026-10-29 07:45-08:35 | 设备: 192.168.161.137:10178 | 开发: hmharness（wg6cbb，有 final 干净交付）| 验收: Zodex 独立复验

## 结论: PASS（两项均超指标）

## A）smoke_reg step7 坐标健壮化

**根因**（hmh 三份 dump 对比实锤）：旧定位 `y1>=60` 过滤——窗口化模式下工具栏整排在 **y1=43**（5 个 36×36 无名 Button）被整排排除 → 「⋮ 未找到」。次生根因：VM 焦点污染（dump 可能抓到终端窗口）。

**修复**（结构树定位，不依赖坐标窗口）：
- `_find_menu_btn()`：以宽≥300 的顶部 TextInput（地址栏）为锚 → 取同 y 带（±8px）、地址栏右侧、≤64px 的 Button 最右者 = ⋮。实测窗口化 [1024,143] / 最大化 [1236,43] 同一逻辑双模式命中
- 焦点防御：dump 归属校验（com.browseros.kaihong），不对则 aa start 拉回重抓
- `--maximize` 改 opt-in（默认窗口化起跑=受测路径）

**验收**：hmh 6 轮 9/9（窗口化×2+最大化×2+终版双模式×2，指标 3 轮）+ **Zodex 独立复跑双模式各 9/9**。

## B）regression_20.py 20 项矩阵

**结果：19 PASS（16 自动化+3 证据引用）+ 1 BLOCKED + 0 FAIL**（指标 PASS≥14）：

- 16 项自动化：冷启动/前台渲染/页面注册/⋮ 菜单结构/书签搜索框/a11y×45/图标像素门/MCP 全家（initialize/navigate/中文站/tabs/history/grep/evaluate/read/会话隔离）
- 3 项证据引用（装机截图+源码双确认）：主题（p44）、语言中英（p50）、DevTools（p47）
- 1 项 BLOCKED（如实）：网页下载——P16 实证 ArkWeb 无下载完成回调、onDownloadStart 之外无落盘钩子，设备侧无法断言（待上游 API 或应用层方案）
- 两轮运行一致 + Zodex 独立复跑同结果

**调试沉淀**（hmh）：MCP 客户端必须先 `tabs{action:new}` 拿自有 tab（P51 -32000）；HTTP 需回传 `Mcp-Session-Id`（-32001）。

## 变更（仅 tools/，应用源码未动）

smoke_reg.py（+100/-37 结构化定位+焦点防御+maximize opt-in）· regression_20.py 新增 · p64 侦查/辅助脚本 4 个

## 证据（evidence/p64/）

EVIDENCE.md · smoke_final_free/max + run1-4（6 轮）· regression_20_report.txt + run2 · 焦点污染对照 dump
