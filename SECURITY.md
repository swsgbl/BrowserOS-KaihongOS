# 安全政策（Security Policy）

## 支持版本

| 版本 | 支持状态 |
|---|---|
| main（P40+） | ✅ 安全修复 |
| 历史 tag | ❌ 请升级到 main |

## 报告漏洞

**请勿通过公开 Issue 报告安全漏洞。**

请通过 GitHub 仓库的 **Report a vulnerability**（Security  Advisories）或 AtomGit 仓库私信提交，内容包括：

- 问题类型（如内存破坏 / 凭据泄露 / 注入）
- 复现路径与影响面
- 如有，PoC 或截图

我们将在 **7 天内**确认收到、**30 天内**给出评估与修复计划；修复发布前请勿公开披露。安全修复会在 CHANGELOG 中致谢报告者（除非要求匿名）。

## 本项目的安全设计（供审计参考）

- **密钥存储**：LLM API Key 经 `@ohos.security.asset`（Asset Store Kit，硬件级安全存储）加密保管；`config.json` 落盘前一律脱敏（字段置空），磁盘上不存在明文密钥；首次启动自动完成明文→asset 的幂等迁移。
- **设备端 MCP 服务**：HTTP（:9222）与 WebSocket（:8765）通道均要求 token 鉴权；token 每次应用冷启动轮换；敏感操作（支付/删除/设置类导航）弹窗人工确认（可配置）。
- **网络安全**：遵循平台禁令，应用内出网仅走 https（明文 http 会被系统层瞬断）；MCP 本机回环除外。
- **无数据收集**：零遥测、零上传；历史/书签/会话仅存于应用沙盒。
- **已知边界**（如实披露）：设备侧签名当前为本地调试证书；正式分发必须替换官方发布证书并走应用市场审核流程。

## 供应链

- CI（GitHub Actions）仅执行仓库内 `tools/static_checks.py`，不引入第三方构建依赖；
- 本仓库不打包任何 SDK 二进制（构建工具链来自本机 DevEco/OpenHarmony SDK）。
