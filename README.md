# BrowserOS - KaihongOS（深开鸿版 BrowserOS）

[BrowserOS](https://github.com/browseros-ai/BrowserOS) 的 1:1 复刻 AI 代理浏览器，运行于 **KaihongOS / OpenHarmony API 14**，使用 ArkTS + ArkUI + ArkWeb 原生实现。上游为基于 Chromium 的开源 AI 浏览器（AGPL-3.0），本项目在鸿蒙平台上完成等价功能栈的移植与复刻。

- **Bundle**: `com.browseros.kaihong`
- **状态**: P1-P31 交付 + R1-R11 审计全收官（见 [DEVPLAN.md](DEVPLAN.md)，权威开发台账）
- **许可**: AGPL-3.0（与上游一致，见 [LICENSE](LICENSE)）

## 功能栈

| 域 | 实现 |
|---|---|
| 浏览器壳 | 竖排标签条（左侧）、hover 自动展开侧边菜单栏、地址栏（9 种搜索引擎）、书签条、上下文菜单、深色/浅色主题实时切换 |
| 新标签页 | Cockpit 仪表盘（hero + 聊天输入框 + 起手提示词 + 快捷磁贴）、MCP 安装板（5 框架 + 46 品牌连接器目录）、LLM 设置、代理创建表单 |
| Agent 引擎 | 15 步代理循环、SSE 流式输出（含回退）、发光遮罩运行态、停止按钮、会话/对话历史双视图侧栏（360vp 停靠） |
| MCP | 设备端 MCP 服务（WebSocket :8765 + HTTP），JSON-RPC 2.0，10 个内置工具，密钥校验；HttpMcpTransport/WsMcpTransport 双通道 |
| 定时任务 | 每小时/每天/每周模型，60s tick 调度，防重入，独立管理页 |
| LLM Hub | 多供应商自定义接入（OpenAI 兼容端点 + API Key），可对接云端或本地 Ollama 兼容服务 |
| 数据 | 历史 RDB + 书签 Preferences 持久化、会话记录与回放播放器（回放/时间线/标签页三视图）、下载管理（进度/重试/取消）、审计日志 |
| 书签导入 | Chrome 导出 bookmarks.html（Netscape 格式）文件选择器导入，URL 去重 |
| 其它页面 | 历史搜索、下载页、LLM Hub、定时任务、设置、Onboarding、View Source、登录态管理 |

### 与上游的架构级替代

| 上游（Chromium） | 本项目（API 14） | 说明 |
|---|---|---|
| Chromium 内核 + chromium_patches | ArkWeb（Web 组件） | 鸿蒙平台无 Chromium 移植，Web 能力由系统 Web 引擎承担 |
| Chrome 扩展生态 | MCP 连接器目录（46 家）+ 设备端 MCP 服务 | ArkWeb 无扩展框架；扩展能力等价物=工具协议接入 |
| Electron/Chrome侧面板 | ArkUI AgentSidePanel 停靠栏 | 等价交互 |
| 一键导入 Chrome 登录/书签 | 书签 HTML 导入 | API 14 无法访问登录数据，按研究报告建议落地“仅本地导入书签” |

## 构建与部署

前置：DevEco Studio / OpenHarmony SDK（API 14 目标设备或 VM）、hdc。

```bash
# 一键：构建 → V1 资源重打包 → 推送 → 设备端签名 → 安装 → 启动 → 桌面快捷方式
python tools/deploy.py

# 跳过桌面快捷方式
python tools/deploy.py --skip-shortcut

# 30 秒健康回归（7 项：设备在线/包安装/冷启动/前台渲染/静态a11y/MCP HTTP/书签入口）
python tools/smoke_reg.py

# 离线静态检查（CI 同款）
python tools/static_checks.py
```

构建链说明：SDK 26 的 hvigorw 产物含 RestoolV2 resources.index，API 14 设备无法解析，`tools/build_v1_hap.py` 用 5.0.1.0.11 restool 重打包为 V1；`tools/install_p8.py` 负责设备端 hap-sign-tool 签名安装。详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 目录结构

```
entry/src/main/ets/
  pages/        11 个页面（BrowserShell 主壳 + 书签/历史/下载/LLM Hub/定时任务/回放/设置/引导/源码）
  components/   竖排标签条、侧边菜单栏、Agent 侧栏、Cockpit 仪表盘、书签条、对话框、上下文菜单
  service/      Agent 引擎、MCP 服务(JSON-RPC/WS/HTTP)、LLM 客户端、标签/书签/历史/下载/定时/会话管理
  protocol/     BCP 引擎、JS 桥注入、截图、快照生成、WebView 适配
  storage/      StorageManager、Preferences、历史 RDB、配置、审计日志
  infra/        EventBus、ErrorHandler、PerformanceMonitor
  model/ common/ 数据模型 / 主题 Palette、9 引擎注册表、常量
tools/          deploy.py / smoke_reg.py / static_checks.py / build_v1_hap.py / install_p8.py ...
evidence/       27 个阶段目录（P1-P31 + R1-R11 设备实证截图与日志）
DEVPLAN.md      权威开发台账（阶段、根因、验收证据）
docs/           架构文档
```

## 平台限制（已知）

- KaihongOS 禁明文 HTTP（http 端点瞬断），全部网络走 https 或设备本地回环。
- ArkWeb API 14 无 Chrome 扩展框架、无 OnDownloadStart suggestedFileName、TextInput 有回灌缺陷（已规避）。
- 当前签名走 VM 本地调试签；真机发布需替换正式证书（见 DEVPLAN「生产就绪」节待项）。

## 许可

AGPL-3.0-or-later（继承上游 BrowserOS 的 AGPL-3.0）。全文见 [LICENSE](LICENSE)。
