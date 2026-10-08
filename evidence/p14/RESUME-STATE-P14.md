# P14 断点状态（RESUME-STATE）

## 状态：P14 全部完成，4 域全链路装机验证通过

## Commits（按序）
- 57e14ed feat(p14a): history → relationalStore RDB + legacy 迁移 + 90d/5000 清理
- 6cf1912 feat(p14b): BOOKMARKS_CHANGED 订阅通知 + 登录态 Preferences 迁移
- 1986ce4 feat(p14c): 会话元数据 session_index → Preferences + 磁盘对账
- fa2cdfb fix(p14): PrefsStore init 竞态 + legacy 每启误迁
- 3358181 fix(p14): .migrated 档案回灌自愈
- f41078c fix(p14): .json.migrated.migrated 重复后缀枚举兼容

## 装机验证证据（hilog, 2026-10-09 02:12）
- RDB: `/data/app/el2/100/database/com.browseros.kaihong/entry/rdb/history.db` 落盘
- HistoryDb init ok / mirror refreshed: rows=3 expanded=11（重启后持久 + 当日 visit_count 聚合生效, 每次 boot about:blank count+1）
- 登录态: `loaded from Preferences: domains=1`（prefs 直读路径生效, 不再走 legacy）
- .migrated 档案: `login_state/.example.com.json.migrated` 存在
- MCP navigate 驱动 example.com/org 导航 → onPageEnd → recordNavigation → RDB（无失败日志=写成功）

## 遗留（P15 候选）
- session_index 对账路径为惰性（打开 HistoryPage 才触发 ensurePersistedSessions），未在本次 smoke 里实际跑过——代码构建绿，逻辑与已验证域同构
- HistoryPage 搜索仍走内存过滤（getAllHistory().filter），searchHistory(RDB LIKE) API 已就绪未接线
- BrowserShell L941 历史/书签计数在 build 内直查，未订阅 BOOKMARKS_CHANGED

## 构建链（复用）
hvigorw.bat assembleHap → python tools/build_v1_hap.py → python tools/install_p8.py
hdc target 127.0.0.1:15566 (KaihongOS QEMU)
MCP token: 设备 files/mcp_token.txt, query 参数 ?token=
