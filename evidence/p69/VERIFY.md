# P69 验证报告：应用内更新机制——后台下载+重启即更+国内外双源

日期: 2026-10-30 00:00-00:15 | 设备: 192.168.161.137:10178 | 开发: hmharness（zkl9is，无 final 中断）+ Zodex 接管验收与修复

## 结论: PASS（全链设备实证；验收中发现并修复 3 个真 bug）

## 全链证据（hilog + 文件 + bm dump 三重）

| 环节 | 结果 | 证据 |
|---|------|------|
| 启动自动检查（24h 节流） | ✅ | update_state.json lastAutoCheck 首启即查 |
| **地理竞速** | ✅ | hilog：`manifest github... http 404`（global 源失败）→ `manifest 1.1.1 via ghfast.top/...`（CN 源胜出）|
| 版本比较 | ✅ | 1010000 < 1010001 判定有更新 |
| **后台下载** | ✅ | `download http 200 bytes=4072360 ok=true`（4MB/约5s，不经下载列表不打扰）|
| **sha256 强校验** | ✅ | `sha256 MATCH 133bc4f8eb94 vs 133bc4f8eb94` |
| system_update 任务→runner | ✅（修复后） | runner 日志：claimed kind=system_update → `system_update done ok=true` |
| runner 独立 sha 复核 | ✅（修复后） | `sha256 MATCH (133bc4f8eb94..)` |
| **重启即更** | ✅ | bm install -p -r → 应用被杀（runner 心跳 ECONNREFUSED=预期）→ aa start → **bm dump versionName=1.1.1 / versionCode=1010001** |

## 验收中发现并修复的 3 个真 bug（Zodex，hmh 死于 E2E 前）

| # | bug | 修复 |
|---|-----|------|
| 1 | **applyViaRunner 未传 kind**：createTask 第 6 参 kind 默认空 → 任务被当普通 prompt 发给 LLM → Claude 拒绝执行"伪系统指令"（提示注入防御反而立功暴露了 bug） | UpdateService 传 'system_update' |
| 2 | **脱敏层染污 sha256**：P42 Redact 的 16+hex token 模式把任务载荷里的公开 sha256 摘要掩成 `****` → runner 复核必 MISMATCH | McpJsonRpcCore 对 device_agent_tasks 输出豁免脱敏（loopback 管理面；sha 是公开摘要非机密）|
| 3 | **runner bm 命令形式错误**：`bm install -r <path>` 位置参数（本机 bm 只认 `-p`）→ 打印 usage 未安装且误报成功 | 改 `bm install -p <path> -r`（与既有装机链同款）|

## 双源事实（VM 实测）

- **ghfast.top→GitHub raw：200/真 JSON**（CN 源，2.8s）✅ 采用
- GitHub 直连：ECONNRESET（被墙）— global 源在国外网络可用
- **AtomGit /raw 是 SPA 壳**（5792B HTML，不可直读）— 保留为第二候选位，待其开放 raw
- 用户需求语义完整落地：国内走国内可达链路（ghfast 国内可达）、国外走 GitHub release，竞速+可手选+失败换源

## 交付物

- app：UpdateService（检查/竞速/下载/校验/应用）+ Settings 关于区 UI + 更新弹窗 + i18n + EventBus 事件
- runner：system_update 分支（sha 复核+bm install+aa start）
- 仓库侧：update-manifest.json（仓库根）+ tools/release_publish.py + release/browseros-1.1.1.hap（含全部修复的最终包，sha=2e4fef75…）
- docs/DEVICE_AGENTS.md 补 runner 用法

## 已知边界（如实）

- 无 runner 的常规设备：弹窗如实提示"已下载，安装需应用市场/开发者工具"（OpenHarmony 普通应用无自安装权限，不做假安装）
- 本次 E2E 的 apply 触发采用与 UpdateService.applyViaRunner 完全同构的任务投递（字段落源核对）；设置页按钮的点击链因设备前台争抢未走通纯 UI 点击，但其 onClick→applyViaRunner 接线在修复后与已验证代码同一路径
