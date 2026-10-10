# P19 验收报告 —— R8 审计三缺口

日期: 2026-10-10 | 基线: 9d123cb → 三笔 commit (b674529 / 6a46136 / aa1a21b)

## A. 侧栏答案回流 (p19a)
**改动**: AgentEngine 新增 `finalAnswers` Map + `getFinalAnswer(agentId)`,任务终态(完成/失败/LLM未配置)落库;AgentSidePanel 1s 轮询 `pollSettled()`,COMPLETED 推答案气泡(500字截断),ERROR/STOPPED 推原因气泡,`settledAgents` 去重,Scroller 绑定 List 滚底,`aboutToDisappear` 清定时器。
**验证**(hilog):
- `AgentSidePanel mounted, agents=0` (08:49:44)
- `AgentSidePanel settle polling stopped` (08:52:59) —— 定时器清理无泄漏
- 重开再 mounted (08:53:13) —— 生命周期完整
**限制**: QEMU 环境 IME 文本注入不可靠,无法 E2E 打字派发任务;轮询/去重/回流代码路径经构建+装机+日志验证。

## B. 清除浏览数据 (p19b)
**改动**: BookmarkManager.clearAllBookmarks / DownloadManager.clearAllDownloads(进行中先 cancel)/ SessionManager.clearAllSessions 三个新服务 API;HistoryPage 顶栏「清除」按钮+全屏确认弹层;SettingsPage 隐私节「清除浏览数据」卡(4 项 Checkbox + 实时计数 + 二次确认行 + 成功提示)。
**验证**(E2E 全链路 PASS):
- 隐私节计数: `hist=65 bm=3 login=1 dl=0 sess=16` (hilog 08:58:04)
- 「清除数据」→「确认清除所选数据？…取消/确认清除」弹层 (布局 08:59:08 `clear confirm shown`)
- 确认后: **浏览历史 65 条 → 0 条**、书签 3 条保留(未勾选)、「已清除所选数据」提示
- hilog: `SettingsPage clearSelected done` + `[SessionManager] clearAllSessions done, removed=16` + `[HistoryManager] clearAllHistory done`
- 重启应用主界面仍「历史 0 条」—— RDB 持久清除
- HistoryPage 路由页: 「历史记录 | 0 条 | 清除 | 🔍 | 🕘 | 暂无历史记录」

## C. 站点权限弹窗 (p19c)
**改动**: BrowserShell Web 链挂 `onPermissionRequest`(SDK14 真实签名 `OnPermissionRequestEvent.request: PermissionRequest`,方法 getOrigin/getAccessibleResource/grant/deny 经 web.d.ts 核实);`showPermDialog` 弹层(origin + 资源中文名 + 阻止/允许),`grantPerm(false)` 兜底 deny,遮罩点击=阻止;资源翻译: 摄像头/麦克风/MIDI 设备/运动传感器。
**验证**: 构建通过+装机启动无崩溃;常规浏览(browseros.com 等站点)无假弹窗;摄像头/麦克风真站点触发需物理媒体设备,QEMU 无法覆盖,弹层逻辑经编译+代码审查验证。

## 遗留
- C 的真权限请求 E2E(需 openstreetmap.org geolocation + 摄像头站点,VM 网络与媒体设备受限)
- A 的 LLM 真任务回流(需 IME 输入;Dashboard 磁贴入口可键盘驱动,可后续补)

## 环境备注
- hdc 目标 127.0.0.1:15566 (KaihongOS QEMU), 部署链 deploy_hap.py (API14 重打+VM 本地签+装)
- bundle 真名 com.browseros.kaihong(非 com.oneaiterm.browseros)
- QEMU 焦点易被 tty7(com.oneaiterm.terminal)抢占,多步点击需紧连执行
- 地址栏右侧图标坐标(1600x900): 历史 1488 / Agent 侧栏 1548 / 三点菜单 1570
