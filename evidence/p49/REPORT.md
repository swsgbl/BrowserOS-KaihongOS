# P49 完成报告：i18n 残留补全 + AI harness 全量集成测试

日期：2026-10-26 ｜ 设备：KaihongOS 6.1.2.08 VM `192.168.161.137:10178` ｜ 提交：`6c4a601`(A) + `51a69db`(B)

## A i18n 残留英文补全（9/9 断言 PASS，zh/en 双语设备验证）

### 语言包
- I18nZh/I18nEn 各 +38 key（`heroSubtitle`/`ultrafastDesc`/`ultrafastCta`/`survey*`×5/`skills*`×2/`sk*`×9/`dt*`×3/`wl*`×14/`menuSkills`），key 对齐校验 **510/510 PASS**（tools/p48_check.cjs）

### 页面迁移（7 文件）
| 文件 | 内容 |
|---|---|
| BrowserShell.ets | hero 副标题、Ultrafast 横幅 desc/CTA/Span×2（任务书外发现的同类残留） |
| JtbdSurveyPage.ets | Welcome 标题/副标题/Start Survey + ThankYou 标题/描述 |
| SkillsPage.ets | 标题/副标题/New skill/表头/详情/Prompt 表单（{n} 占位符复用 itemsN 模式） |
| UltrafastWaitlistPage.ets | 整页 14 处（PERKS 数组/COMING SOON/价格行/表单校验），新增 I18n import + locale 锚 |
| DevToolsPage.ets | Console/Network/Info 标签数组 |
| ChromeWidgets.ets | ⋮ 菜单 Skills 项（i18n 后 zh=技能） |
| PasswordsPage.ets | 核查后已全走 I18n，未动 |

### 🔴 附带修复：P48 重大回归（private get → method）
**根因**：P48 提交 3c94642 把组件字段从 `private readonly x = [...]` 改为 `private get x()`。ArkUI struct 内 **getter 被 ForEach/@Builder 消费时子项静默丢弃**：
- ⋮ 菜单塌缩为只剩「退出」行（4 条 1px Divider + Exit）
- 设置页左导航空白（搜索引擎区直接顶到内容区）
- AgentSidePanel 模型下拉、JtbdSurvey 问题列表同病
**修复**（4 处 getter → 普通方法 + 调用点补括号）：ChromeWidgets `group1/2/3`、SettingsPage `navItems`、AgentSidePanel `modelOptions`、JtbdSurvey `QUESTIONS`。修复后菜单 15 项/设置页 5 分区全渲染。

### 设备验证（tools/p49_i18n_verify3.cjs + p49_banner_verify.cjs）
- zh：hero「选择任一已连接的服务商或代理…」✓ 菜单「技能」✓ Skills 页（技能/次数/节省令牌/未统计）✓ 横幅「更快的浏览器任务」+「申请抢先体验 →」✓ waitlist（即将推出/加入等待名单/自带 Claude）✓
- en：hero "Pick any provider…" ✓ Skills (New skill/Runs/Tokens saved) ✓ banner "Faster browser tasks" ✓ waitlist (COMING SOON/Join waitlist/$5/mo) ✓
- 语言切换 zh→en→zh 回路 ✓（设置→外观→English/中文）
- 证据：evidence/p49/*.jpeg（双语截图 12 张）+ layout dumps

### 环境坑（已固化到脚本）
- 设备休眠锁屏 → `power-shell wakeup` + 上滑 + 点登录钮 (640,645)
- 解锁后 app 为自由窗口 → 点 `EnhanceMaximizeBtn` 恢复全屏坐标
- banner 不显示 = ultrafast_joined/dismissed prefs 持久态 → 清 `preferences/ultrafast_store*`

## B AI harness 全量集成测试（41/41 + 5/5 PASS）

### B1 MCP 协议兼容（tools/harness_compat_test.py，30 项）
6 家 harness clientInfo × 完整链路（initialize[含各家 capabilities 差异]→tools/list[17 工具+inputSchema 校验]→tools/call navigate/snapshot/read）：
**claude-code**（roots.listChanged+sampling）✓ **codex**（sampling only）✓ **cursor-ide**（roots）✓ **deepseek-generic**（零能力极简客户端）✓ **windsurf** ✓ **vscode-generic** ✓
- 双会话并发交错调用（claude-code × codex，独立 TCP 连接，3 轮 tabs/read/history 无串台）✓

### B2 配置 JSON 契约（6 项）
对每家 harness 校验 `generateMCPConfigJSON` 产出：`{"mcpServers":{"browseros-kaihongos":{"url":"http://127.0.0.1:<port>/sse?token=<t>","transport":"sse"}}}`（loopback + token 内嵌）✓×6

### B3 设备端 MCP 安装板（tools/p49_b3_panel.cjs，5/5）
「查看代理」→「MCP 安装板」：本地端点 URL+token 展示（http://<本机IP>:9222/mcp?token=…）✓ harness 网格（Claude Code/Codex/Cursor/VS Code 卡片）✓ 连接器目录 46+ 家（GitHub/Notion/Figma/Linear…滚动累计 47 名）✓ 截图 evidence/p49/b3_*.jpeg

### B4 agent e2e（4 项）
MCP 全链路：navigate example.com → snapshot（返回真实多语言页面文案，2024 版 example.com 已无 "Example Domain" H1——断言已校准为实际内容）→ read 往返 → hilog 875KB 日志含 MCP 轨迹 ✓

### 回归门禁
- static_checks.py：**all passed**（91 ArkTS 文件/SVG 45/a11y 42）
- smoke_reg.py：**9/9 PASS**（两处修复：① 第 8 项菜单断言 i18n 感知（技能|Skills）② 新增 `_maximize_window` 预处理自由窗口，修好第 4/7 项环境性失败）

## 提交
- `6c4a601` feat(p49a): i18n 残留补全 + P48 getter 回归修复
- `51a69db` feat(p49b): harness 全量互通 + smoke 修复（33 files, +542）
