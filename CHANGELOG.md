# 更新日志（Changelog）

本项目的逐阶段完整台账见 [DEVPLAN.md](DEVPLAN.md)（含根因分析与设备证据）；本文件按里程碑精编。

格式参考 Keep a Changelog；版本以仓库主分支阶段号标记。

## [P56 / v0.1.0-beta] - 2026-10-28
### 工程化
- **release 打包**：`release/BrowserOS-KaihongOS-v0.1.0-beta-signed.hap`（3,836,406 B，API 23，VM 端签名）；INSTALL.md/SHA256SUMS.txt 同步更新；git tag `v0.1.0-beta`
- **台账同步**：README/CHANGELOG/DEVPLAN/ARCHITECTURE/SECURITY 全部更新至 P56 状态
- 验证：static 37/37 + smoke 9/9（装机实测）

## [P55] - 2026-10-27
### 新增
- **Stable SnapshotRef**：跨工具调用稳定的快照引用语义（navigate→snapshot→read/diff 链路引用一致）
- **tab_groups**：标签组管理（创建/列取/清理，对齐上游 tab-group cleanup da5f95e 语义）
- **windows/wait/evaluate 语义**：windows 列取真实窗口/tab 维度、wait 条件等待（可超时）、evaluate 页内表达式求值——MCP 17 工具语义级对齐收官

## [P54] - 2026-10-27
### 新增
- **AuditEventBus**：统一审计事件总线（内部 agent 循环 + 外部 MCP 工具调用同源汇聚）
- **tab 定向截图**：screenshot 工具支持指定 tab（非仅活动页）
- **AuditPage**：审计事件查看页（时间线/来源/脱敏详情）

## [P53] - 2026-10-27
### 新增
- **登录态导入向导**（ImportWizardPage）：分步引导导入
- **Profile 隔离**：导入凭据与运行时隔离
- **Upload/PDF capability**：upload/pdf 工具按平台能力如实上报与执行（能力探测闭环）

## [P52] - 2026-10-27
### 变更
- **MCP 协议 2026-07-28 协商**：echo 请求版本或回退 2024-11-05；capabilities 声明 resources/prompts；serverInfo name=browseros_mcp+title；版本取自 bundleManager
- **统一 endpoint `/mcp`**：McpEndpointConfig 单一真值源（含 fport 命令生成）
- **HarnessAdapters**：claude-code/codex/cursor/generic 四种 per-CLI 配置形状一键生成
- **连接状态真实化**：connect()=配置就绪（不再假 Connected）；testConnection()=真实 initialize 握手（200+serverInfo）；harness_connected_<name> 持久化；Connect 对话框 Test 按钮实时判定
- harness_compat_test.py 40/40 PASS（设备两轮）

## [P51] - 2026-10-27
### 新增
- **McpSessionStore**：MCP 会话隔离（session-id 校验 + tab ownership + 并发隔离）
- **AuditRedactor**：审计输出系统级脱敏
- **凭据加密迁移**：CredentialStore 以 Asset Store 为主真值源（P47 明文→硬件加密迁移）
### 修复
- **地址栏残留根治**：setOmniboxText() 唯一写入口（过滤 about:blank/空），收口 6 处程序化赋值
- 标签栏折叠（24vp 窄条）/拖宽（120-400 clamp）/持久化
- 侧栏 i18n（9 组件 localeVersion 渲染锚 + @Builder 值参数缓存规避）

## [P50] - 2026-10-26
### 变更
- 设置入口可达性：⋮ 菜单 Settings 升 group1 pos2（原 group3 row9 被 constraintSize 420 裁剪）；设置导航外观优先；语言切换升外观顶部卡片（pill 按钮）；深链搜索索引同步

## [P49] - 2026-10-26
### 新增
- i18n 收官：语言包 510/510（zh/en），6 页迁移（hero/ultrafast/survey/skills/waitlist/devtools）；修复 P48 回归（getter-in-struct ForEach 静默丢项）
- **AI harness 全互操作**：harness_compat_test.py 41/41（6 harness × initialize+tools/list+call 链；B2 配置契约；B1 双会话并发；B4 agent e2e）
- MCP 安装板 5/5（endpoint+token、harness 网格、46 连接器目录）；smoke 9/9（i18n 感知断言）

## [P47-P48] - 2026-10-25 ~ 10-26
### 新增
- **密码管理器**：CredentialStore + PasswordsPage + 自动填充/保存条（P47）
- **DevTools Console 页**：console 日志采集 + 网络请求记录（P47）
- **无痕标签页**（Web incognitoMode）+ **缩放控制**（P47b）
- **i18n 框架**：zh/en 切换、473 词条初版、350+ 硬编码迁移（P48）

## [P44-P46] - 2026-10-25
### 新增/修复
- 全局深浅主题实时渲染（18 页组件 @StorageProp @Watch+themeVersion 锚，P44）
- 竖排标签 +/× 修复（@Prop 缺失致子组件不刷新）、omnibox 全选、空标签清理（P45）
- 侧栏折叠开关、新标签默认标题 BrowserOS、聊天输入搜索图标、Android 格式 SVG 修复（P46）

## [P42-P43] - 2026-10-25
### 新增
- 外部 96 项差距矩阵收口（8 真缺口全修：loopback/CSPRNG/敏感 gate/脱敏/会话清理/html2canvas 本地化/localhost 白名单/发布工程）；UPSTREAM_BASELINE.md + verify_mirrors.py + tag v0.1.0-alpha
- **MCP 10→17 工具**（对齐上游 registry 同名同序）；限流 McpRateLimiter（30req/10s/连接，HTTP 429/WS -32000）；mcp_client_e2e.py 15 项门禁 14/15（WS 握手 header 匹配 pending）

## [P40] - 2026-10-24
### 新增
- MCP `initialize` 响应注入 `instructions` 引导字段（对齐上游 da5f95e）
### 修复
- **API23 全应用图标空白**：根因为 API23 改包脚本使用 ZIP_DEFLATED，而 KaihongOS 6.x 包读取器仅支持 ZIP_STORED；重打包改为 STORED+保序后冷启动资源错误 61→0，图标像素门禁 36.5% 真实通过

## [P39] - 2026-10-24
### 变更
- **环境大迁移**：支持 KaihongOS 6.1.2.08 / API 23 / PC 形态（VMware）；V2 资源索引直装取代 V1 重打包链；新增 `tools/build_api23_hap.py`（SDK26 构建+后处理 min/target=23）；宿主与设备双端签名材料链
- smoke：MCP 隧道改走宿主 19222 高位端口（9222 被本机占用）

## [P38] - 2026-10-20
### 变更
- 全应用 121 处图标引用迁移至 `$rawfile`（39 枚），与资源 id 体系解耦，杜绝 id 漂移导致的图标空白
### 新增
- smoke 第 9 步「图标像素门禁」（dump 定位→截图→非背景像素≥15%）
- static 检查项：禁止新代码使用 `$r('app.media.ic_*')`
- `tools/perf_probe.py` 性能采样；签名 profile 可再生配方

## [P37] - 2026-10-18
### 修复
- 全应用图标空白回退（用户报告"+"消失/×失灵的真相）：清理重编导致 hvigor 资源 id 重排，与 V1 打包钉死的历史 id 错位；新增 `tools/gen_final_ids.py` 从构建产物二进制索引解析权威 id 自动同步

## [P36] - 2026-10-18
### 新增
- LLM API Key 迁移至 Asset Store Kit 硬件级加密；config.json 全脱敏（磁盘零明文密钥）；幂等迁移
- `docs/PERFORMANCE.md` 性能基线（冷启动 55-60ms / PSS 161MB @VM）；smoke 扩至 8 步
### 移除
- 硬编码 XOR 伪加密实现

## [P35] - 2026-10-18
### 新增
- jtbd 调查弹窗（消息阈值触发）与三问调查页
- Ultrafast 等待列表页（价格/权益/邮箱校验），横幅 CTA 改跳转
- 新标签页 agent-command 对齐（hero 句式/Provider 选择器/RecentSites/ScheduleResults）

## [P33-P34] - 2026-10-17
### 新增
- 聊天上下文四件套：页面选中文本捕获、Chat/Agent 模式切换（单轮直答）、附加标签 chip、更新日志弹窗
- 驾驶舱 1:1：三段式 hero、Ultrafast 横幅、Skills 台账页（Run/次数持久化）

## [P32] - 2026-10-17
### 新增
- Chrome 书签 HTML 导入（Netscape 格式/去重）；AGPL-3.0 LICENSE；README/架构文档；GitHub Actions CI；`tools/static_checks.py` 离线检查
### 修复
- smoke 第 7 步历史性失败根因（uinput 点击注入无效→uitest；hdc 调用未带 `-t` 导致 recv 静默失败）

## [P28-P31] - 2026-10-12 ~ 10-15
### 变更
- 原生布局重构：竖排标签条+hover 侧边菜单栏；新标签页聊天输入框；冷启动默认落新标签页
### 修复
- 竖排标签 +/× 按钮（透明度/触摸目标/事件优先三层）；主题实时切换（@StorageProp 不触发 @Builder 的规避）

## [P23-P27] - 2026-10-11 ~ 10-12
### 新增
- 定时任务（时/日/周调度）、LLM Hub 多供应商、MCP 连接器目录（46 家）、回放页三视图
### 修复
- 桌面图标替换为上游官方像素源；全图标体系统一审计

## [P16-P22] - 2026-10-09 ~ 10-10
### 新增
- 下载管理、标签持久化恢复、页内查找、错误横幅、9 引擎搜索选择器、a11y 标注、smoke 回归脚本、AI 侧栏停靠重构（Chrome 原生上下文对齐）

## [P1-P15] - 2026-10-05 ~ 10-09
### 里程碑
- 真实 Web 渲染内核（ArkWeb）、Agent 引擎（LLM 循环/SSE/快照）、MCP 服务端（HTTP+WebSocket JSON-RPC）、持久层（RDB/Preferences）、会话录制回放、Chrome 系 UI 体系、29+ SVG 图标、右键菜单、书签/历史/下载页、深色主题
