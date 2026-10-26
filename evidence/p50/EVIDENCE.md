# P50 证据:设置页可达性修复 + 语言切换入口显性化

设备:192.168.161.137:10178 (KaihongOS VM) · 时间:2026-10-26 22:31-22:50 · 构建:d598633+

## 代码改动
| 文件 | 改动 |
|---|---|
| ChromeWidgets.ets | ⋮ 菜单「设置」从 group3 第 9 行(菜单卡 constraintSize 420 不可滚,实际被裁剪——用户找不到入口的根因)移到 group1 第 2 位,首屏可见 |
| SettingsPage.ets | ① navItems 外观置首(默认选中即外观区);② 右内容区索引映射同步(0=外观 1=AI 2=搜索);③ P18 搜索深链 navSelection=2;④ 语言切换从外观区底部文字链提升为**首卡**:标题「界面语言 / UI Language」(双语常量键 stLangCardTitle)+ 中文/English 胶囊按钮(选中实心蓝) |
| I18nZh/En.ets | +1 键 stLangCardTitle(zh/en 511/511,p48_check PASS) |

## D 节 7 步验证结果(截图+dumpLayout 双证)
| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | ⋮ 菜单打开,设置首屏可见 | ✅ 菜单第 2 项=设置 @[1072,139](原第 9 行被裁) | step1_menu_real.jpeg / layout6.json |
| 2 | 设置页左导航 6 项完整,默认外观区,语言卡首屏 | ✅ 外观/AI/搜索/隐私/MCP/关于;首卡「界面语言 / UI Language」+ 中文/English 胶囊 | step2_settings_appearance.jpeg / layout7.json |
| 3 | 点 English → 持久化 en | ✅ hilog 22:42:16 `locale persisted: en`;按钮变蓝选中 | step3_english_clicked.jpeg |
| 4 | 重启 → en 保持,整页英文 | ✅ 冷启 `init done locale=en`;新标签页全英文(New tab/View agent/Import login state) | step4_restart_en.jpeg |
| 5 | 重进设置(英文态入口验证) | ✅ 菜单 Settings@第2位 → Appearance/Language/Theme/Dark mode 全英文 | step5_settings_en.jpeg / layout10.json |
| 6 | 点中文 → 持久化 zh | ✅ hilog 22:48:51 `locale persisted: zh` | step6_back_zh.jpeg / layout11.json |
| 7 | 重启 → zh 保持 | ✅ 冷启 `init done locale=zh`(22:50:19);新标签页全中文 | step7_restart_zh.jpeg |

hilog .locale 轨迹: zh(22:31) → en(22:42 持久化) → en(22:45 重启回读) → zh(22:48 持久化) → zh(22:50 重启回读) —— 写入/回读闭环完整。

## 已知行为(非本次范围)
- 语言切换后设置页自身文案不即时翻转(需返回再进/重启),P48 框架 navItems ForEach key 未含 locale 所致;主界面(BrowserShell)有 localeVersion 锚会即时刷。本次验证以重启回读为准,简报 D 节无即时翻转要求。

## 构建链
harmony_build(SUCCESSFUL) → tools/build_api23_hap.py(STORED 3.4MB) → tools/install_p8.py(VM 签名+bm install -r+启动 OK)

## 过程坑(新)
- **edit_file 并行写同文件竞态**:同一文件两个 edit 并行调用,后写者基于旧内容覆盖,导致前一个补丁丢失+文件尾注入脏块(brace balance -6)。修复:node 脚本清脏尾+重放全部补丁+tokenizer 验括号平衡。后续同文件多处修改必须串行或走脚本。
- ⋮ 真实坐标是 [1244,51][1264,71] 中心(1254,61);[1208,51] 是 Agent 面板切换钮。
- dumpLayout attributes 是对象,坐标在 `bounds` 键,type 在 attributes.type。
