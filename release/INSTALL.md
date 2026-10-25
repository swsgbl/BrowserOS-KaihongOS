# BrowserOS KaihongOS v0.1.0-alpha 安装说明

## 安装包

`BrowserOS-KaihongOS-v0.1.0-alpha-signed.hap`（约 2.8 MB，API 23，已签名）

## 适用环境

- KaihongOS 6.x（API 23，PC 形态，如 Kaihong PC）
- 需要 hdc（HarmonyOS Device Connector）工具

## 安装步骤

```bash
# 1. 连接设备
hdc tconn <设备IP>:<端口>

# 2. 推送安装包
hdc file send BrowserOS-KaihongOS-v0.1.0-alpha-signed.hap /data/local/tmp/browseros.hap

# 3. 安装
hdc shell bm install -p /data/local/tmp/browseros.hap -r

# 4. 启动
hdc shell aa start -a EntryAbility -b com.browseros.kaihong
```

## 首次启动

- Onboarding 引导页（可跳过）
- 建议在设置→AI 中配置 LLM 端点（如 https://apihub.agnes-ai.com/v1 + API Key）
- 新标签页含聊天输入框、RecentSites、MCP 安装板

## 已知限制

- ArkWeb 无 Chrome 扩展框架（用 MCP 46 连接器替代）
- ArkWeb 无 printToPDF（pdf 工具返回 unsupported）
- KaihongOS 禁明文 HTTP（应用内仅 https）
- 签名为本地调试证书（正式分发需替换）

## 校验

SHA-256 见同目录 SHA256SUMS.txt
