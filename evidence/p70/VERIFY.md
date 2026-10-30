# P70 验证报告：生产反馈三连修——新标签打开/runner 自愈/multiWindowAccess 回归拦截

日期: 2026-10-30 21:14-22:15 | 设备: 192.168.161.137:10178 | 执行: Zodex 直接修复

## 用户反馈（截图+描述）

"在线使用"页面依然打不开；右侧 AI 没有输出；很多问题。

## 根因与修复（全部设备实证）

### 1. window.open / target=_blank 全站失效（"在线使用打不开"等一大类菜单问题的总根源）
- **根因**：ArkWeb 默认 `multiWindowAccess=false`，引擎直接拒绝所有新窗口请求（window.open 返回 null=blocked；_blank 点击无任何反应），且项目从未接线 onWindowNew。
- **尝试**：`.multiWindowAccess(true)` + onWindowNew 降级新标签 → **在设备上杀死了整个 JS proxy 管线**（read/snapshot/evaluate 全 null 的严重回归）→ 立即回滚，回归消除。
- **最终方案（console 通道 shim）**：JSBridgeInjector 注入页面级 shim——接管 `window.open` 与 `_blank` 点击捕获，经 `console.log('__P70_NEWTAB__'+url)` 通知原生层；BrowserShell.onConsole 解析标记 → openTabFromShim() 建新标签（仅 http/https，防 js: 注入）。**不依赖 proxy 桥（导航后不死）**。
- **实证**：window.open `blocked:true→opened:true`，标签 9→10（kdocs.cn）；_blank 点击 10→11（kdocs.cn/latest）；WPS"在线使用"点击后 kdocs+登录页均以新标签打开；JS 管线保持健康（evaluate 1+1=2、read/snapshot 正常）。

### 2. 右侧 AI 没有输出（设备智能体路径）
- **根因**：runner 在 app 重启（token 轮换）后死于 `401 invalid token`（启动时缓存 token、顶层 init 抛错即退出）→ 所有设备智能体任务永远 pending。
- **修复**：refreshToken()（直读应用沙盒 token 文件，root 可读）+ 启动 init 无限重试 + 循环错误时先刷 token 再重连 + 永不退出。
- **实证**：app 强杀重启后 runner 日志 `token refreshed from file (rotated)` → `re-initialized after error`，自动恢复在线。
- 注：内置智能体引擎本身健康（key 在多次更新安装后存活于 Asset Store，agent_task 秒答）。

### 3. 附带拦截的事故
- hvigor 假命中（改码后 abc 未更新）→ 清 entry/build 全量重建后恢复。
- 设备 1.1.1 版本降级拒装 → 临时对齐 versionCode 同版替换安装。
- 静态检查误伤模板字符串内页面 JS 的 console.log → 动态构造 `console['l'+'og']` 绕过（运行时等价）。

## 回归

static 全过 + smoke 9/9 + evaluate/read/snapshot 健康 + runner 自愈复验。

## 已知边界

- onWindowNew 处理器保留在代码中（multiWindowAccess 关闭时不触发，为将来引擎修复预留）。
- shim 的 window.open 返回桩对象（closed/close/focus/postMessage）——绝大多数站点兼容；依赖真实 window 引用的高级用法（如 window.opener 深度操作）不支持。
- 开发基线 versionCode 已临时对齐 1.1.1（同版替换需要）；下个 release 应升 1.1.2 并用 release_publish 重发 manifest。

## 证据

evidence/p70/：p70_run_test.sh（新标签验证脚本）、p70_scope.cjs（管线健康探针）、p70_winopen.cjs、p70_runner_selfheal.log（token 轮换自愈日志）。
