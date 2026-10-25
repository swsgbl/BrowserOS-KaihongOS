# 上游基线声明（UPSTREAM BASELINE）

> 本文件声明本项目与其上游的关系、对标形态与架构级替代，供合规审查与溯源使用。
> P42（KAI 发布工程）引入，随发布 tag（v0.1.0-alpha）一同固化。

## 1. 上游项目

| 项 | 值 |
|---|---|
| 上游仓库 | https://github.com/browseros-ai/BrowserOS |
| 上游形态 | BrowserOS **neo** —— 面向 AI Agent 的 Chromium 开源浏览器 |
| 上游许可 | AGPL-3.0 |
| 对标方式 | **行为级 1:1 复刻**（非源码 fork）——按上游 main 分支的界面结构、交互与 Agent 能力栈，在 OpenHarmony/ArkTS 上重新实现 |
| 上游 commit 锚定 | 上游为持续演进的 main 分支；本仓库以 P1-P42 各阶段任务书中的对标快照为准（侧栏双路由、12 屏全量对齐等，详见 DEVPLAN.md） |

**本项目不是上游的 fork**：无任何上游源码（TypeScript/React/Chromium C++）拷贝；
所有代码为 ArkTS/ArkUI 原生实现，仅对其交互行为与信息架构做等价复刻。
许可同为 AGPL-3.0 以保持兼容（见 LICENSE / NOTICE）。

## 2. 对标形态（BrowserOS neo）

- 浏览器壳：竖排标签条 + hover 侧边菜单 + 地址栏（9 搜索引擎）+ 书签条 + 上下文菜单 + 深浅主题
- Agent 侧栏：Chat / History 双视图，MCP 工具协议（navigate/click/type/screenshot/snapshot/scroll/getText/wait/back/forward）
- 12 屏全量对齐（BrowserShell / Onboarding / Settings / History / Bookmarks / Downloads / Sessions / Skills / JTBD 调研 / Ultrafast 候选等）

## 3. 架构级替代表

| 上游（Chromium/TS） | 本项目（OpenHarmony） |
|---|---|
| Chromium 内核 | ArkWeb（webview） |
| React + HashRouter | ArkUI 声明式 + 页面路由 + 组件状态切换 |
| Playwright/CDP 驱动 | BCP 协议（JSBridge 注入 + runJavaScript 回调） |
| MCP Server（Node） | ArkTS MCP Server（HTTP 9222 / WS 8765，loopback-only，token 鉴权） |
| Chromium 截图 | html2canvas 1.4.1（rawfile 本地化注入，P42） |
| Chrome 扩展宿主 | HAP 单包 + Skills 页面 |

## 4. 镜像与发布

| 远端 | 地址 |
|---|---|
| origin | https://github.com/swsgbl/BrowserOS-KaihongOS.git |
| atomgit | https://atomgit.com/hongfu/BrowserOS-KaihongOS.git |

- 镜像校验工具：`tools/verify_mirrors.py`（三方 HEAD 比对）
- 首个发布 tag：**v0.1.0-alpha**（P42 安全加固收口：loopback 绑定 / CSPRNG token / type 敏感 gate / 输出脱敏 / 会话按时间清理 / html2canvas 本地化 / localhost 白名单）
