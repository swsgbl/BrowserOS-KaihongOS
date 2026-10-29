# P64 证据:测试基建健壮化(smoke 坐标修复 + 20 项回归矩阵)

日期:2026-10-29 · 设备:192.168.161.137:10178 (KaihongOS 6.1.2.08 API23 VMware VM) · 基线:a9d656a

## A) smoke_reg.py step7 坐标定位修复 — 完成

### 根因(三种 dump 对比实证)
- 旧定位 = 固定坐标窗口过滤(`y1>=60 and y1<=400 and x1>=1000` 取最右 Button)。
- **窗口化模式**下工具栏整排在 y1=43(P49「窗口化 toolbar 下移」的真相:冷启动自由窗口时工具栏 y 带 37-79,最大化时 43-79,但**旧 y1>=60 下限把窗口化整排 36x36 按钮全部排除**),→ 「⋮ 菜单按钮未找到」(P63 smoke_run1 实锤,见 evidence/p63/p63_smoke.txt)。
- 次生根因:VM 焦点污染——dump 可能抓到别的 app(p64_focus_pollution_terminal.json 实锤抓到 com.kaihong.terminal),旧代码不校验 dump 归属。

### 修复方案(结构化定位,方案一「结构树定位」胜出)
1. **`_find_menu_btn()` 结构不变量定位**:锚=顶部宽>=300 的 TextInput 地址栏(两模式都存在)→ 取同 y 带(cy∈锚±8px)、位于地址栏右侧(x1>=max(锚右缘,600))、尺寸<=64px 的图标 Button 中最右者 = ⋮。Enhance* 系统窗控按 id 排除。
   - 最大化实测:锚[?]+⋮[1236,43][1272,79];窗口化实测(p64_free_after_restore.json):锚[568,145][871,177]+⋮[1024,143][1060,179] —— **同一逻辑两种模式直接命中**。
2. **焦点防御**:step7 dump 后校验 `com.browseros.kaihong` 归属,不对则 `aa start` 拉回重抓;重试点击链同样先拉前台+重新结构定位(菜单未开时首击可能被动画/焦点吞)。
3. **`_maximize_window` 改 opt-in**:新增 `--maximize` flag(默认关),使窗口化模式成为受测路径而非被消除的变量。
4. **`_grab()` helper** 统一 dump+recv+read 重复逻辑。

### 验收(超指标:6 轮 9/9,含两种模式)
| 轮次 | 起跑模式 | 结果 | 文件 |
|---|---|---|---|
| run2 | 窗口化 | 9/9 | smoke_run2_free.txt |
| run3 | 窗口化→--maximize | 9/9 | smoke_run3_max.txt |
| run4 | 最大化状态起跑 | 9/9 | smoke_run4_maxstart.txt |
| final-free | 还原自由窗口 | 9/9 | smoke_final_free.txt |
| final-max | --maximize | 9/9 | smoke_final_max.txt |
(run1 控制台记录=smoke_run1_free_console.txt;指标要求 3 轮含两种模式,实跑 5 轮存档 9/9)

## B) regression_20.py 20 项矩阵 — 完成(19 PASS + 1 BLOCKED ≥ 14 指标)

判定分三类:自动化(P)、证据引用(PASS-CITE,历史装机实证+源码确认)、BLOCKED(设备侧客观阻塞)。

| # | 功能 | 判定 | 证据 |
|---|---|---|---|
| 01 | 冷启动生命周期 | PASS(自动) | hilog onCreate/onForeground |
| 02 | 前台渲染标题+地址栏 | PASS(自动) | dumpLayout BrowserOS+TextInput |
| 03 | MCP HTTP initialize | PASS(自动) | serverInfo ok(会话头 Mcp-Session-Id) |
| 04 | navigate+snapshot | PASS(自动) | example.com snapshot len=1021 |
| 05 | navigate 中文站 | PASS(自动) | baidu title=百度一下，你就知道 |
| 06 | tabs new/list/close | PASS(自动) | tab_1_xxx listed+close ok |
| 07 | history back/forward | PASS(自动) | body url=baidu.com action=back |
| 08 | grep 可见文本 | PASS(自动) | IANA Reserved 3 hits |
| 09 | evaluate_in_page | PASS(自动) | document.title=Example Domain |
| 10 | read 页面正文 | PASS(自动) | len=1028 |
| 11 | 会话隔离读 | PASS(自动) | 双会话 s1 read 无 IANA 泄漏(P62-B 模式) |
| 12 | ⋮ 菜单结构 | PASS(自动) | 菜单项 4/4 书签/设置/技能/历史 |
| 13 | 书签页搜索框 | PASS(自动) | placeholder 搜索书签(=修复后 smoke step7) |
| 14 | 图标渲染像素门 | PASS(自动) | non-bg 24.2%>=15 |
| 15 | 无障碍标注(静态) | PASS(自动) | accessibilityText x45>=20 |
| 16 | 页面注册完整性 | PASS(自动) | main_pages 13 页 |
| 17 | 主题深浅切换 | PASS-CITE | evidence/p44/t2-settings-dark.jpeg+t3-newtab-dark.jpeg+源码确认 |
| 18 | 语言中英切换 | PASS-CITE | evidence/p50/step4_restart_en.jpeg+step7_restart_zh.jpeg+I18n 源码确认 |
| 19 | DevTools 控制台/求值 | PASS-CITE | evidence/p47/g2-devtools.json(87KB)+g5-eval.json(87KB) |
| 20 | 网页下载 | BLOCKED | P16 实证:ArkWeb 无下载完成回调,无落盘钩子,待上游/应用层方案 |

两轮稳定:PASS 19(含引用 3)/ FAIL 0 / BLOCKED 1(regression_20_report.txt + regression_20_run2.txt)。

### 踩坑记录(本轮新增)
- **P51 会话-标签模型**:MCP 新会话必须先 `tabs{action:new}` 拿自有 tab 才能 navigate/read/evaluate,否则 -32000 "session owns no tab";HTTP 会话必须带 `Mcp-Session-Id` 头(initialize 响应头取),否则 -32001。
- 语言切换证据在 evidence/p50(P50 任务),非 p48。
- regression_20 里 UI 链偶发菜单未开(2/4 轮):重试链需「拉前台+重新结构定位再点」而非原坐标重点;修复后连续两轮 4/4。

## 变更清单(仅 tools/,未动应用源码)
- tools/smoke_reg.py — 结构化定位+焦点防御+opt-in maximize+_grab helper
- tools/regression_20.py — 新增,20 项矩阵(MCP 客户端带会话头+P51 tab 归属)
- tools/p64_probe.py / p64_probe2.py / p64_cmp.cjs — dump 对比侦查(保留供复现)
- tools/p64_restore_free.py — 还原自由窗口 helper(验收用)
- tools/p64_dbg_menu.py — 菜单链诊断脚本
