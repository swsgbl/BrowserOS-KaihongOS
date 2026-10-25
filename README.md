# BrowserOS - KaihongOS（深开鸿版 BrowserOS）

[![CI](https://github.com/swsgbl/BrowserOS-KaihongOS/actions/workflows/ci.yml/badge.svg)](https://github.com/swsgbl/BrowserOS-KaihongOS/actions/workflows/ci.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)

[BrowserOS](https://github.com/browseros-ai/BrowserOS) 的 1:1 复刻 AI 代理浏览器，原生运行于 **KaihongOS（深开鸿）/ OpenHarmony**，ArkTS + ArkUI + ArkWeb 实现。上游为基于 Chromium 的开源 AI 浏览器（AGPL-3.0），本项目在鸿蒙平台上完成等价功能栈的移植与复刻，并已完成上游 12 屏界面的全量对齐。

- **Bundle**: `com.browseros.kaihong`
- **支持环境**: KaihongOS 5.0（API 14，平板/窗口形态）与 **KaihongOS 6.x（API 23，PC 形态）** 双环境
- **状态**: P1-P40 交付 + R1-R11 审计全收官（见 [DEVPLAN.md](DEVPLAN.md) 权威开发台账、[CHANGELOG.md](CHANGELOG.md)）
- **许可**: AGPL-3.0（与上游一致，见 [LICENSE](LICENSE)）；第三方声明见 [NOTICE](NOTICE)

## 功能栈

| 域 | 实现 |
|---|---|
| 浏览器壳 | 竖排标签条（左侧，与上游 v0.42+ 一致）、hover 自动展开侧边菜单栏、地址栏（9 种搜索引擎）、书签条、上下文菜单、深色/浅色主题实时切换 |
| 新标签页 | agent-command 主输入（hero + provider 选择器 + RecentSites + ScheduleResults）、Cockpit 仪表盘（Ultrafast 横幅 + 磁贴 + MCP 安装板 5 框架/46 连接器 + 代理创建） |
| Agent 引擎 | 15 步代理循环、SSE 流式输出（含回退）、Chat/Agent 双模式（单轮直答/工具循环）、页面辉光运行态+停止、选中文本捕获为上下文、附加标签 chip、360vp 停靠侧栏 |
| MCP | 设备端 MCP 服务（WebSocket :8765 + HTTP），JSON-RPC 2.0，10 个内置工具，initialize 携带 instructions 引导，密钥校验 |
| 定时任务 | 每小时/每天/每周模型，60s tick 调度，防重入，独立管理页 + 新标签页结果卡 |
| LLM Hub | 多供应商自定义接入（OpenAI 兼容端点 + API Key），可对接云端或本地 Ollama 兼容服务 |
| 安全 | LLM API Key 硬件级加密存储（@ohos.security.asset），config.json 全脱敏，明文密钥零落盘 |
| 数据 | 历史 RDB + 书签 Preferences、会话录制与回放播放器（回放/时间线/标签页）、下载管理、审计日志、Chrome 书签 HTML 导入（Netscape 格式，URL 去重） |
| 其它 | jtbd 调查弹窗与问答流、Ultrafast 等待列表页、Skills 台账（Run=派发代理）、更新日志通知、Onboarding、View Source、登录态管理 |

### 与上游的架构级替代

| 上游（Chromium） | 本项目（OpenHarmony） | 说明 |
|---|---|---|
| Chromium 内核 + chromium_patches | ArkWeb（Web 组件） | 鸿蒙平台无 Chromium 移植，Web 能力由系统 Web 引擎承担 |
| Chrome 扩展生态 | MCP 连接器目录（46 家）+ 设备端 MCP 服务 | ArkWeb 无扩展框架；扩展能力等价物=工具协议接入 |
| Electron/Chrome 侧面板 | ArkUI AgentSidePanel 停靠栏 | 等价交互 |
| 一键导入 Chrome 登录/书签 | 书签 HTML 导入 | 平台无法访问登录数据，落地"仅本地导入书签" |

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
python tools/static_checks.py      # 离线 16 项（CI 同款）
python tools/perf_probe.py         # 冷启动/内存采样
```

## 文档

- [DEVPLAN.md](DEVPLAN.md) — 权威开发台账（P1-P40 全阶段、根因与设备证据）
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架构与模块职责
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md) — 性能基线
- [CHANGELOG.md](CHANGELOG.md) — 版本变更日志
- [CONTRIBUTING.md](CONTRIBUTING.md) — 贡献指南
- [SECURITY.md](SECURITY.md) — 安全政策与漏洞报告
- [NOTICE](NOTICE) — 第三方作品声明

## 合规声明

- 本项目为 [browseros-ai/BrowserOS](https://github.com/browseros-ai/BrowserOS)（AGPL-3.0）的衍生作品，遵循 AGPL-3.0 完整源码开放义务，未改动部分的权利归属原作者；
- 应用图标使用上游仓库 `docs/logo/favicon.png` 像素源；界面图标为 Material Icons（Apache-2.0）风格的自绘 SVG；
- 本项目不收集、不上传任何用户数据；LLM 密钥仅存储于设备硬件安全区（Asset Store Kit），详见 [SECURITY.md](SECURITY.md)；
- 商标声明：BrowserOS 为上游项目名称；KaihongOS/深开鸿为深圳开鸿数字产业发展有限公司的操作系统名称——本项目为独立的技术移植研究，与上述各方无从属或背书关系。

## 平台限制（已知）

- KaihongOS 禁明文 HTTP（应用内网络必须 https 或设备本地回环）。
- ArkWeb 无 Chrome 扩展框架、OnDownloadStart 无 suggestedFileName（API14）、TextInput 存在回灌缺陷（已规避）。
- 设备侧签名当前使用本地调试证书；正式发布需替换官方发布证书。

## 许可

AGPL-3.0-or-later（继承上游 BrowserOS 的 AGPL-3.0）。全文见 [LICENSE](LICENSE)。
