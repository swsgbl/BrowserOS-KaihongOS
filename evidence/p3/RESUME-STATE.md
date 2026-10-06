# P3 装机阶段 RESUME-STATE（编码棒完成交接）

日期：2026-10-06 ｜ 编码：hmh ｜ 状态：**编码+构建全部完成，未装机**（VM/daemon 被 oneaiterm 争用，装机由 Zodex 发令）

## 产物
- 新建 `entry/src/main/ets/service/HttpMcpTransport.ets`（MCP Streamable HTTP 传输层，TCPSocketServer）
- 修改 `service/MCPServer.ets`（start/stop 真接线 HttpMcpTransport，implements McpHttpDelegate，getToolNames）
- 修改 `entryability/EntryAbility.ets`（onCreate 拉起 MCPServer，onDestroy 停）
- 新建 `scripts/mcp_smoke.py`（宿主侧 6 用例冒烟）
- P2 修复：BrowserShell.isUrl 端口号 / LLMClient catch 属性探测 / TabManager agent tab 标题 / BrowserShell ForEach keyGenerator
- 构建：`entry/build/default/outputs/default/entry-default-unsigned.hap`（BUILD SUCCESSFUL，warn 12 均存量）
- patch 脚本留档：patch_p3_mcp.cjs / patch_p3_wire.cjs / patch_p3_berr.cjs / append_p3_report.cjs

## 装机步骤（复用既有管线）
1. repack API14：repack_hap.py（module.json/pack.info 换 API14 版）→ entry-api14-v7-unsigned.hap（新版本号）
2. hdc send → VM 内 hap-sign-tool 签名（OpenHarmony.p12 pwd 123456 + app1-profile-release.p7b，bundle=com.browseros.kaihong）→ bm install -r
3. aa start 后 hilog 断言：`MCP-HTTP listening on 0.0.0.0:9222` + `EntryAbility MCPServer started on port 9222`
4. 端口转发：VM 9222 → 宿主（qemu hostfwd 或 hdc fwd tcp:9222 tcp:9222）
5. 冒烟：`python scripts/mcp_smoke.py --host 127.0.0.1 --port 9222`（无 token 先跑 401/405/404 三负向用例）

## 装机阶段已知风险（编码棒交付的诚实清单）
1. **token 外显缺失**：authToken 每次启动随机生成，未写文件/hilog。正向用例（initialize/tools/*）跑不了——装机前需 Zodex 决策 token 外显方案（写 files/mcp_token.txt 或固定 hilog 输出），或临时改 EntryAbility 用固定 token
2. **TCPSocketServer.close() d.ts @since 20**：API14 设备 stop() 可能 warn 不释放端口（连接已逐个 close 兜底）；装机若遇端口复用失败→重启应用进程验证
3. 9222 端口冲突：start 失败走 MCP_004 错误日志（hilog 查 `[MCPServer]` / `[MCP-HTTP]` tag），不盲重试
4. agent tab 验收路径：创建 agent → BrowserShell 标签栏应出现「Agent xxxxxx」tab → 点击 → Web 挂载（hilog `onControllerAttached tabId=` + `registered webview adapter`）→ BCP 工具可用

## hilog 观测 tag
- `[MCP-HTTP]`：listening / client connected / 请求行留痕 / rpc method / 401 / send failed
- `[MCPServer]`：started
- `EntryAbility MCPServer`：启动链成败
