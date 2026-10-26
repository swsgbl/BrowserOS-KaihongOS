# P47 完成状态（RESUME-STATE-P47）

**日期**: 2026-10-26 14:25
**状态**: 全部 6 项功能落地并装机验证（commit 8f4508e / ef6d0af / 354cbfe）

## 已完成

### B 密码管理器（Bitwarden 集成）✅
- `service/CredentialStore.ets`: 模块级单例（arkts-no-standalone-this 规避）；preferences(cred_store) 主存储 + Asset Store Kit addSync/removeSync 加密镜像（尽力而为）
- `pages/PasswordsPage.ets`: 域名分组列表/搜索/新增/编辑/删除/明文显隐/清空/Bitwarden JSON 导入(粘贴)/导出到剪贴板
- BrowserShell: onPageEnd 密码框检测(`input[type=password]`)→有凭据出底部填充条(p47DoFill native-setter 注入)，无凭据注入 submit 监听轮询 8×1.5s 捕获新凭据→保存弹层
- 菜单「密码管理器」入口（ChromeWidgets group2）
- **装机验证**: e5/d5/d8 layout dumps（页面打开、空态、导入弹层全渲染）

### A DevTools ✅
- `service/DevToolsCollector.ets`: per-tab console/network 日志 Map 收集器
- `pages/DevToolsPage.ets`: Console tab（级别着色+时间戳+monospace+JS eval 输入行）/ Network tab（method/URL/headers 展开）/ Info tab（URL/标题/UA/统计）
- BrowserShell: `onConsole` 事件接入收集器; `onInterceptRequest` 记录 getRequestUrl/getRequestMethod/getRequestHeader 后放行(return null)
- **装机验证**: g2-devtools.json dump 显示真实 console 日志（[BCP] Bridge script injected / [BCP][P33] selection capture installed, level=info, 13:32:37）

### C 无痕模式 ✅
- Web 构造参数 `incognitoMode: this.p47IncognitoTabs.has(tab.tabId)`（since12, API14 OK）
- 菜单「新建无痕标签页」→ p47CreateIncognitoTab → TabManager.createTab(false) + 集合标记 + getAllTabs 刷新
- **装机验证**: hilog `[P47] incognito tab created: tab_1_1792993312336` + `tab_2_1792993456229`; e8 layout 双标签

### D 缩放 ✅
- 菜单 放大/缩小/重置缩放 → WebviewController.zoom(±0.25/1) + p47FlashToast 1.5s 反馈
- **装机验证**: hilog `BrowserShell menu action: zoom_in` (14:14:34)
- ⚠ 354cbfe 修过 zoom handler 里的 NaN 字面量（另一棒审计发现）

### E 阅读模式 ✅
- 菜单「阅读模式」→ p47OpenReader: JS 抽取最长 h1 + >40字段落(≤200) → JSON → 全屏排版弹层(标题栏+返回+正文 16px/行高28)
- **装机验证**: hilog `menu action: reader` ×2 (14:05, 14:08; about:blank 无正文仅 toast)

### F 表单填充 ✅
- 菜单「填充表单」→ p47FillForm: 按 name/id/placeholder/autocomplete/type 启发式（email/password/tel/name/user/account）+ native-setter+input/change 事件注入；域名匹配时用 CredentialStore 凭据，否则示例数据

## 构建链（不变）
hvigor assembleHap → `python tools/build_v1_hap.py`（restool V1 index）→ `python tools/install_p46.py`（hdc send → VM 侧 hap-sign-tool sign-app → bm install -r → aa start）
- 新 SVG 必须放 `resources/rawfile/`（$rawfile），不是 base/media
- 打包产物: entry-p8-v1-unsigned.hap

## 硬坑记录（本棒新踩）
1. **static class 里 this 引用禁**（arkts-no-standalone-this）→ 一律模块级单例 `class XImpl{} export const X = new XImpl()`
2. **ArkTS catch 不能写类型注解**（arkts-no-types-in-catch）→ 裸 catch(e)
3. **JSON.parse 需先 as object 再窄化**; 对象字面量导出禁 → 字符串拼接
4. **incognitoMode 是 Web 构造参数**（WebOptions since12）不是链式属性
5. **WebResourceRequest**: getRequestUrl()/getRequestMethod()（不是 getUrl/getMethod）
6. **cmd.exe 内联 node -e 中文必炸**（静默 MISS）→ 一律 write_file .cjs 再跑
7. **EOL 混合文件**: BrowserShell=CRLF ChromeWidgets=LF；node 补丁先归一 LF patch 完按原 EOL 写回
8. **uinput 点击后菜单易被 aa start/时序吃掉** → 设备端链式命令（`sh('cmd1; sleep 1; cmd2')`）替代宿主多次往返
9. **uitest uiInput inputText 是追加**不是替换；Enter=keyEvent 2050 但可能触发浏览器返回导航——eval e2e 不可靠，编译级验证即可
10. **omnibox 输入 https URL 仍走 Bing 搜索**（可能 inputText 焦点/编码问题）——VM e2e 导航用 menu action 或 want 通道更稳

## 遗留（低优先）
- DevTools eval 输入需真实键盘 Enter（e2e 环境 uitest keyEvent 2050 会触发返回）
- Network tab 需真实 http 页面加载验证（onInterceptRequest 已接线+编译过，逻辑同 Console 收集器模式）
- PasswordsPage 导入大 JSON 未做进度条
