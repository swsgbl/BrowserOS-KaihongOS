# P52-2 断点（2026-10-27 19:40，P52-2 代码+验证完成，commit 待打）

## 状态：P52-2 已完成（本棒）

### 已完成
1. **McpEndpointConfig.ets 补完**：{protocol,host,port,path:'/mcp',token,transport:'streamable-http'}、`fromServer()`、`toUrl()/toUrlWithToken()`、`getEndpoint()`、`lanUrlWithToken()`、`fportCommand(target)`
2. **HarnessAdapters.ets 补完**：4 adapter（claude-code `~/.claude.json` `{type:'http',url}` / codex `~/.codex/config.json` `{transport:'http',url}` / cursor `~/.cursor/mcp.json` `{url}` / generic）+ `buildConfigJson/getFportCommand/getClipboardText/list/get`
3. **ConnectionManager.ets 重写**：
   - `init(context)` 注入 harness_store preferences（EntryAbility onWindowStageCreate 调用）
   - `detectInstalledTools()` 返回 4 adapter（detected 恒 false = 设备上无宿主 CLI，UI 走 config-ready 状态机）
   - `connect(name)` = 生成配置 JSON 存沙盒 `{name}_mcp.json` + CONNECTING 状态 + `config_ready` 事件（不再假 connected）
   - `testConnection(name)` = **真实握手**：设备本机 POST `http://127.0.0.1:{port}/mcp?token=` initialize（protocolVersion 2024-11-05），200 + `result.serverInfo.name==='browseros_mcp'` 才 `markConnected`（Preferences `harness_connected_<name>=timestamp` + connected 事件）
   - `disconnect/markConnected/getConnectedTools/generateMCPConfigJSON(alias)`
4. **NeoDashboardPanel Connect 弹层**：JSON 配置块 + **fport 命令块**（点击复制）+ **Test 按钮**（真实握手，成功绿 'Connected ✓'，失败红 ✗+原因）+ 状态反馈行
5. **harness_compat_test.py 升级**：P51 会话隔离适配（Mcp-Session-Id header 提取/携带）+ b2 契约改 per-harness 形状（/mcp 统一）+ 调用链先 `tabs{action:new}` + 断言收紧（`r.get('result') is not None`）
6. **验证**：40/40 PASS（复跑 2 次，1 次 38/40 为 example.com 加载抖动）；装机 pid 18178；hilog `[P52] harness_store prefs ready`；4 份真实 token 配置 JSON 落盘 evidence/p52/

### 构建装机链（沿用）
- hvigor assembleHap → `py tools/build_final_v1.py` → `py tools/build_v1_hap.py`（V1 index, API14）→ `py tools/install_p52.py`（设备侧签名+bm install+launch）
- 旧 install_p52.py 曾指向 hvigor 产物导致 9568297（API26 index），已修指向 entry-p8-v1-unsigned.hap

### 下棒（P52-3）
- NeoDashboardPanel/OnboardingPage 状态机细节截图证据（Connect→ConfigReady→Test→Connected UI 流）
- smoke_reg.py 9 步回归
- commit p52-2（service 层 + UI + 测试）→ p52-3（证据+断点）
- 红线照旧：不碰 D:\oneaiterm/、不重启 VM、attic/hmh_state.json 勿碰
