# BrowserOS - KaihongOS（深开鸿版 BrowserOS）

[![CI](https://github.com/swsgbl/BrowserOS-KaihongOS/actions/workflows/ci.yml/badge.svg)](https://github.com/swsgbl/BrowserOS-KaihongOS/actions/workflows/ci.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/badge/release-v0.1.0--beta-blue.svg)](release/)

[BrowserOS](https://github.com/browseros-ai/BrowserOS) 的 1:1 复刻 AI 代理浏览器，原生运行于 **KaihongOS（深开鸿）/ OpenHarmony**，ArkTS + ArkUI + ArkWeb 实现。上游为基于 Chromium 的开源 AI 浏览器（AGPL-3.0），本项目在鸿蒙平台上完成等价功能栈的移植与复刻，并已完成上游 12 屏界面的全量对齐。

- **Bundle**: `com.browseros.kaihong`
- **支持环境**: KaihongOS 5.0（API 14，平板/窗口形态）与 **KaihongOS 6.x（API 23，PC 形态）** 双环境
- **状态**: **P1-P56 全阶段收官**（内部复刻 P1-P40 + 审计 R1-R11 + 外部优化方案 P42-P56），当前发布 **v0.1.0-beta**（见 [release/](release/)）
- **许可**: AGPL-3.0（与上游一致，见 [LICENSE](LICENSE)）；第三方声明见 [NOTICE](NOTICE)

## 功能栈

| 域 | 实现 |
|---|---|
| 浏览器壳 | 竖排标签条（可折叠 24vp/拖宽 120-400vp，与上游 v0.42+ 一致）、hover 自动展开侧边菜单栏、地址栏（9 种搜索引擎，空态放大镜/https 锁图标）、书签条、上下文菜单、深色/浅色主题实时切换、**无痕标签页**、**页面缩放控制**、**阅读模式** |
| 新标签页 | agent-command 主输入（hero + provider 选择器 + RecentSites + ScheduleResults）、Cockpit 仪表盘（Ultrafast 横幅 + 磁贴 + MCP 安装板 5 框架/46 连接器 + 代理创建） |
| Agent 引擎 | 15 步代理循环、SSE 流式输出（含回退）、Chat/Agent 双模式、页面辉光运行态+停止、选中文本捕获为上下文、附加标签 chip、360vp 停靠侧栏 |
| **i18n** | **中英双语界面切换**（510 条语言包 zh/en，即时生效+持久化；侧栏/菜单/设置/弹窗全量覆盖） |
| **密码管理器** | **Bitwarden 兼容导入 + 保存/自动填充条 + PasswordsPage**；凭据经 Asset Store Kit 硬件级加密 |
| **DevTools Console** | 页面 console 日志采集（onConsole/onInterceptRequest 网络请求记录）+ 独立 DevTools 页面 |
| MCP | 设备端 MCP 服务（统一 endpoint `/mcp`，协议 2026-07-28 协商兼容 2024-11-05），JSON-RPC 2.0，**17 个工具**（对齐上游 registry：tabs/tab_groups/history/navigate/snapshot/diff/act/download/upload/read/grep/screenshot/pdf/wait/windows/evaluate/run），限流 30req/10s/连接，**session 隔离**（McpSessionStore，session-id 校验+tab ownership） |
| **Harness Adapter** | Claude Code / Codex / Cursor / Generic 四种 AI harness 的一键配置（per-CLI config 形状）+ **真实连接测试**（initialize 握手，不再假 Connected）；6 家 harness 互操作 41/41 |
| **Audit** | **统一事件总线 AuditEventBus**（内部 agent + 外部 MCP 工具调用同源审计）+ AuditPage 查看 + **AuditRedactor 脱敏**（输出/日志系统级敏感信息遮蔽） |
| 定时任务 | 每小时/每天/每周模型，60s tick 调度，防重入，独立管理页 + 新标签页结果卡 |
| LLM Hub | 多供应商自定义接入（OpenAI 兼容端点 + API Key），可对接云端或本地 Ollama 兼容服务 |
| 安全 | LLM API Key 与登录态凭据 **Asset Store 硬件级加密**（P51 起 CredentialStore 主真值源）、config.json 全脱敏、明文密钥零落盘、MCP token 轮换 + 敏感操作人工确认 |
| 数据 | 历史 RDB + 书签 Preferences、会话录制与回放播放器、下载管理、Chrome 书签 HTML 导入（Netscape 格式去重）、**登录态导入向导**（Profile 隔离 + Upload/PDF capability） |
| 其它 | jtbd 调查弹窗、Ultrafast 等待列表页、Skills 台账、更新日志通知、Onboarding、View Source、**Stable SnapshotRef + tab_groups/windows/wait/evaluate 语义**（P55） |

### 与上游的架构级替代

| 上游（Chromium） | 本项目（OpenHarmony） | 说明 |
|---|---|---|
| Chromium 内核 + chromium_patches | ArkWeb（Web 组件） | 鸿蒙平台无 Chromium 移植，Web 能力由系统 Web 引擎承担 |
| Chrome 扩展生态 | MCP 连接器目录（46 家）+ 设备端 MCP 服务 | ArkWeb 无扩展框架；扩展能力等价物=工具协议接入 |
| Electron/Chrome 侧面板 | ArkUI AgentSidePanel 停靠栏 | 等价交互 |
| 一键导入 Chrome 登录/书签 | 书签 HTML 导入 + 登录态导入向导 | 平台无法直接访问登录数据，落地"本地导入" |

## 构建与部署

前置：DevEco Studio（SDK 26 工具链）、hdc、目标设备（KaihongOS 5.0/6.x 或对应 VM）。

```bash
# API 23（KaihongOS 6.x，推荐）：构建 → API23 改包(注意 zip 必须 STORED) → 设备端签名安装
hvigorw.bat assembleHap --mode module -p product=default --no-daemon
python tools/build_api23_hap.py
# 设备端签名安装见 docs/ARCHITECTURE.md「构建链」

# API 14（KaihongOS 5.0）：V1 资源重打包链
python tools/deploy.py

# 回归
python tools/smoke_reg.py          # 设备在环 9 步（含图标像素门禁）
python tools/static_checks.py      # 离线静态检查（CI 同款）
python tools/mcp_client_e2e.py     # MCP 客户端互操作 15 项门禁
python tools/perf_probe.py         # 冷启动/内存采样
```

## 文档

- [DEVPLAN.md](DEVPLAN.md) — 权威开发台账（P1-P56 全阶段、根因与设备证据）
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架构与模块职责
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md) — 性能基线
- [CHANGELOG.md](CHANGELOG.md) — 版本变更日志
- [CONTRIBUTING.md](CONTRIBUTING.md) — 贡献指南
- [SECURITY.md](SECURITY.md) — 安全政策与漏洞报告
- [UPSTREAM_BASELINE.md](UPSTREAM_BASELINE.md) — 上游基线与镜像核验
- [NOTICE](NOTICE) — 第三方作品声明

## 合规声明

- 本项目为 [browseros-ai/BrowserOS](https://github.com/browseros-ai/BrowserOS)（AGPL-3.0）的衍生作品，遵循 AGPL-3.0 完整源码开放义务，未改动部分的权利归属原作者；
- 应用图标使用上游仓库 `docs/logo/favicon.png` 像素源；界面图标为 Material Icons（Apache-2.0）风格的自绘 SVG；
- 本项目不收集、不上传任何用户数据；LLM 密钥与登录凭据仅存储于设备硬件安全区（Asset Store Kit），详见 [SECURITY.md](SECURITY.md)；
- 商标声明：BrowserOS 为上游项目名称；KaihongOS/深开鸿为深圳开鸿数字产业发展有限公司的操作系统名称——本项目为独立的技术移植研究，与上述各方无从属或背书关系。

## 平台限制（已知）

- KaihongOS 禁明文 HTTP（应用内网络必须 https 或设备本地回环）。
- ArkWeb 无 Chrome 扩展框架、OnDownloadStart 无 suggestedFileName（API14）、TextInput 存在回灌缺陷（已规避）、printToPDF 缺失（pdf 工具按能力探测）。
- 设备侧签名当前使用本地调试证书；正式发布需替换官方发布证书。

## 许可

AGPL-3.0-or-later（继承上游 BrowserOS 的 AGPL-3.0）。全文见 [LICENSE](LICENSE)。
