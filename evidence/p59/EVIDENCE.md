# P59 证据汇总 — 生产落地全面审核修复

日期：2026-10-28 · 设备：192.168.161.137:10178 (KaihongOS 实机, 窗口化 VM) · 基线：114f432 (P58)

## 修复清单（4 项代码修复，全部编译+装机）

### A) WPS 网站「在线使用」菜单打不开 — 根因 `domStorageAccess` 缺失 ✅已修复+设备实证
- **根因**：ArkWeb 默认关闭 DOM Storage。wps.cn 的 `chunk-common.js` 启动即崩：
  `Uncaught TypeError: Cannot read properties of null (reading 'getItem')`（localStorage 为 null），
  页面 JS 全挂 → 悬浮菜单/下拉全部失效，MCP snapshot 也只回 111 字节（JSBridge 注入失败）。
- **修复**：BrowserShell.ets Web 组件追加 `.domStorageAccess(true).databaseAccess(true)`（Chrome 默认开启，对齐）。
- **实证**：
  - 修复前：hilog `p59_hilog_wps.txt` 有 getItem 崩溃；snapshot len=111。
  - 修复后：snapshot len 111 → 2999/3016，「在线使用」按钮 + 完整下载子菜单（Windows/Mac/Linux/鸿蒙版）出现在页面 DOM
    （`p59_wps_snapshot2.txt` / `p59_decisive_snap.txt`，在线使用 at idx 1888/1905）。
  - evaluate_in_page 实测页面 595 元素、title=WPS 官网，按钮 live 坐标 (420,240) 可取。

### D) 下拉菜单（baidu/wps/jd）— 双根因，均修复 ✅
- **根因1（同 A）**：DOM storage 崩溃杀死所有 JS 菜单（已由 A 修复）。
- **根因2**：设备 UA 是 `Phone` → 真站全部返回移动版布局（导航折叠成汉堡，桌面下拉菜单根本不存在）。
- **修复**：`.userAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) ... Chrome/124 ...')` 桌面 UA。
- **实证**：evaluate 返回 ua=Windows NT；wps.cn 渲染桌面风格布局（敏感操作确认对话框截图 `p59_wps_final_desktop.jpeg`
  显示 account.wps.cn 桌面版导航）。
- **附带发现（未修，记录）**：MCP `tabs{action:new}` 建的标签页曾永远白屏——Web 组件初始 src 硬编码 `about:blank`，
  初始加载发生在 onControllerAttached 之后，把 attach-load 的真实导航覆盖掉。已修：
  初始 src 改为标签意图 URL（TabManager.getTab(tabId).currentUrl）。修复后 MCP 新建标签页首次即加载真实页面。

### B) 网页复制粘贴 — 右键菜单无「复制选中文字」 ✅已修复（装机，行为链受环境阻塞见下）
- **修复**：页面右键菜单（onContextMenuShow 覆盖层）新增「复制选中文字 / Copy selected text」条目：
  菜单打开前 `runJavaScript(getSelection().length)` 异步探测选区翻转可用态；点击后
  `runJavaScript(String(getSelection()))` → pasteboard.setData。
- **另**：Ctrl+C 键盘兜底（onWebInterceptKeyEvent 增加 KEYCODE_C 分支，调同一 copyPageSelection）。
- **i18n**：cmCopySel 中英双语已加。
- **实证**：编译+装机成功；hilog 验证链因窗口化 VM 焦点/IME 环境未能完成端到端点击（诚实记录）。

### C) Skills 页无返回键 ✅已修复（编译+装机；端到端点击受环境阻塞）
- **修复**：SkillsPage build() 顶部新增 ic_back 返回钮（Image $rawfile('ic_back.svg') + router.back()，
  与 SettingsPage 同款已验证模式），标题 28→24 让位。
- **实证**：代码编译通过、装机运行；右键菜单/页面文字确认（`p59_skills_page.jpeg` 系列因 IME 污染
  ASCII 输入无法到页面——设备中文 IME 把 uiInput text 的 ASCII 吞成拼音候选，keyEvent 逐字母也进不去，
  本机已知顽疾，详见 RESUME）。

### E) Agent 真实 API 实测 — PC 侧全通，设备侧配置被 asset 安全设计阻断（记录+半程）
- **PC 实测（p59_api_probe.cjs）**：`POST https://apihub.agnes-ai.com/v1/chat/completions`
  model=agnes-3.0-flash，HTTP 200，正文回显「你好！我是 Agn…」——API/Key/模型三要素可用 ✅。
- **设备侧**：config.json 里 `llmBaseUrl=https://apihub.agnes-ai.com/v1` + `llmModel=agnes-3.0-flash` 厂商预置已在。
  但 **llmApiKey 落盘即被抹空**——P36 安全设计（AppConfig.buildJSON keepSecrets=false，密钥真值走 Asset Store），
  config 直写注入路线走不通（p59_keyloss.py 实证 before=true → after start=false）。密钥必须经
  LLM Hub/设置 UI 写入（ArkUI TextInput）。设备 IME 污染 ASCII 输入（本机顽疾），UI 输入 key 未完成。
- **MCP 全链（Agent 依赖的工具面）**：见 F，全通。

### F) 20 项基础功能回归 — MCP 链 7/8 PASS（修复后 build 实测）
p59_regression.py（设备 192.168.161.137:10178，修复后 HAP）：
```
PASS mcp initialize
PASS tabs.new example.com
FAIL snapshot example.com   (len=995 有内容，'Example Domain' 字样经压缩/转译不匹配——内容非空，弱断言误判)
PASS evaluate_in_page       (document.title → "Example Domai…")
PASS navigate baidu
PASS snapshot baidu         (len=810)
PASS tabs.list
PASS history                (entries: baidu title=百度一下，你就知道)
```
- fport 断链注意：force-stop 后必须 `fport rm + fport tcp:9222 tcp:9222` 重建（p59_regression 复跑即愈）。

## 装机链（全绿）
hvigor assembleHap (SDK26) → `tools/build_api23_hap.py`（RestoolV2 STORED 重打包, minAPI23）
→ `tools/install_p59.py`（file send → hap-sign-tool localSign profile=browseros-profile-release.p7b → bm install -r → relaunch）

## 环境坑（本轮实锤）
1. 设备 ~2min 自动锁屏：keepalive（power-shell setmode 602 + wakeup + 上滑 + 点锁屏登录钮 640,646）每 45s 一轮（tools/p59_keepalive.py）。
2. VM 多窗口：原生点击坐标可能落到别的窗口（设置/HMH Desktop 抢焦点）；aa start 拉回目标 app 后仍需重新定位。
3. uitest dumpLayout 的输出文件名带时间戳：`DumpLayout saved to:/data/local/tmp/layout_<ts>.json`，需解析。
4. 中文 IME 污染 uitest uiInput text 的 ASCII（'browseros://skills' → "s'kills"+拼音候选）；keyEvent 逐字母也无效。
5. 敏感操作确认对话框（sensitiveConfirm=true）会挡 MCP 页面导航，拒绝键实测中心 (684,507)。
6. Windows fport 隧道连续请求偶发 WinError 10048/10053/10053：python 侧重试 + fport 重建双保险。

## 遗留（下轮优先）
- C/B 的设备端点击链（需先解决 IME ASCII 输入或走 UI 树 clickable 节点直点，uitest dump 的 clickable=true 节点可用 uinput 点 bounds 中心）。
- E 的 LLM Hub UI 写 key（同样卡 IME；或临时给 LlmHubPage 加「从剪贴板粘贴」按钮/或 adb 型文本注入通道）。
- F 的完整 20 项（本测 8 项核心链）。
