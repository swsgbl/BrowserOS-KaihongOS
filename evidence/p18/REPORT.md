# P18 验收报告：搜索引擎完整功能（commit 955edd0）

任务书 `.zcode/p18_brief.md`。基线 1c53e8b（P17 收官）→ 本棒交付 A/B/C 三阶段。

## 实施内容（21 处补丁，6 文件）

| 阶段 | 文件 | 内容 |
|---|---|---|
| A 注册表 | common/SearchEngines.ets（新） | SearchEngine 类 + SEARCH_ENGINES×9 + getEngineById 回退 google |
| B 持久化 | model/AppConfig.ets | searchEngineId 字段 + toJSON + fromJSON 容错（旧配置→'google'） |
| B 持久化 | storage/ConfigManager.ets | set() 处理新字段 + getSearchEngineId() |
| B 切换 | pages/SettingsPage.ets | 导航首位「搜索」节：当前引擎行 + 更改弹层 + 9 引擎单选列表（选中即存） |
| B fallback | pages/BrowserShell.ets | onAddressInput: Constants 硬编码 → getEngineById(getSearchEngineId()).queryUrl 拼接 |
| C 显示 | components/ChromeWidgets.ets | 建议首行渲染引擎名 title + 底栏「搜索引擎 · X \| 切换」+ onSwitchEngine 回调 |
| C 深链 | BrowserShell + SettingsPage | 切换 → router.pushUrl settings?section=search → aboutToAppear 直达 navSelection=0 |

## 实机验证（VM 127.0.0.1:15566，harmony build → build_v1_hap → install_p8 链）

| # | 项 | 证据 | 结果 |
|---|---|---|---|
| 1 | 设置页搜索节渲染（9 引擎全列出） | dump-engine-list.json + settings-engine-list.jpeg | ✅ |
| 2 | 切换百度：UI 即时变更 | p18_l9（当前引擎=百度+wd= 模板）| ✅ |
| 3 | 持久化落盘 | 沙盒 config.json `"searchEngineId":"baidu"` | ✅ |
| 4 | hilog 行为日志 | `SettingsPage searchEngine switched: baidu` | ✅ |
| 5 | 重启保持 | 重启后建议首行仍「百度 搜索」 | ✅ |
| 6 | omnibox 引擎显示 | 建议首行`百度 搜索 xx`+底栏`搜索引擎 · 百度`+`切换`（omnibox-engine-display.jpeg） | ✅ |

## 遗留（如实记录）
- 端到端导航截图（纯文本回车→地址栏变 baidu.com/s?wd=）未截得：uinput -K -t 只追加不清选区（`about:blank`+`zz`=`about:blankzz`，about: 前缀走 URL 分支不经搜索 fallback）+ dshapp(com.oneaiterm.terminal) 反复抢前台。onAddressInput 的 fallback 与建议首行/设置页同源（getEngineById(ConfigManager.getSearchEngineId())），数据源五路实证均为 baidu，代码链路无分支疑点。待手动环境输入纯文本一键复验。

## 本棒新坑（已记忆固化候选）
- dumpLayout attributes 是**对象**（{name:value}）非数组——本项目 walker 已修（.verify/p18_walk.cjs 通用）
- dshapp 抢前台升级：kill -9 后 ~3s 自愈重启，只能每步杀+拉，UI 自动化步数预算要留足
- PowerShell here-string 经 cmd 引号必炸，DEVPLAN 追加一律走 node 脚本
