# BrowserOS KaihongOS v0.1.0-beta 安装说明

## 安装包

`BrowserOS-KaihongOS-v0.1.0-beta-signed.hap`（约 3.8 MB，API 23，已签名）

本版本为 P1-P56 外部优化方案全收官后的 beta 快照（含 MCP 17 工具 / i18n 中英双语 / 密码管理器 / DevTools Console / 无痕模式 / Audit 事件总线 / Harness Adapter 等，详见仓库 CHANGELOG.md）。

## 适用环境

- KaihongOS 6.x（API 23，PC 形态，如 Kaihong PC）
- 需要 hdc（HarmonyOS Device Connector）工具

## 安装步骤

```bash
# 1. 连接设备
hdc tconn <设备IP>:<端口>

# 2. 推送安装包
hdc file send BrowserOS-KaihongOS-v0.1.0-beta-signed.hap /data/local/tmp/browseros.hap

# 3. 安装
hdc shell bm install -p /data/local/tmp/browseros.hap -r

# 4. 启动
hdc shell aa start -a EntryAbility -b com.browseros.kaihong
```

## 首次启动

- Onboarding 引导页（可跳过）
- 建议在设置→AI 中配置 LLM 端点（如 https://apihub.agnes-ai.com/v1 + API Key）——密钥经 Asset Store Kit 硬件级加密存储，磁盘零明文
- 新标签页含聊天输入框、RecentSites、MCP 安装板
- 界面语言可在 设置→外观→界面语言 中英切换（即时生效并持久化）

## AI Harness 接入（MCP）

- 设备端 MCP 服务统一 endpoint：`/mcp`（协议版本 2026-07-28 协商，兼容 2024-11-05）
- 驾驶舱「Connect」面板提供 Claude Code / Codex / Cursor / Generic 四种 harness 的一键配置命令与真实连接测试（Test 按钮，握手成功才显示 connected）
- 具体端口映射命令见应用内 Connect 对话框（hdc fport）

## 已知限制

- ArkWeb 无 Chrome 扩展框架（用 MCP 46 连接器替代）
- ArkWeb 无 printToPDF（pdf 工具按能力探测，受平台支持限制）
- KaihongOS 禁明文 HTTP（应用内仅 https；MCP 走本机回环例外）
- 签名为本地调试证书（正式分发需替换）

## 校验

SHA-256 见同目录 SHA256SUMS.txt
