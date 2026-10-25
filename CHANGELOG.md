# 更新日志（Changelog）

本项目的逐阶段完整台账见 [DEVPLAN.md](DEVPLAN.md)（含根因分析与设备证据）；本文件按里程碑精编。

格式参考 Keep a Changelog；版本以仓库主分支阶段号标记。

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
