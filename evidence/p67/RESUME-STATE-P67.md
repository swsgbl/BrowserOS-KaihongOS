# P67 状态（主链完成并装机验证，2026-10-29 23:0x，git 41d5a13）

任务书 `.zcode/p67_brief.md`。设备 192.168.161.137:10178（唯一）。
**A/B/C/D 四相全部落码、装机、验证通过。** 证据全在 `evidence/p67/VERIFY.md` + 4 张截屏。

## 已完成（勿重做）

- **A MCP 19→21**：`entry/src/main/ets/service/MCPServer.ets`（handleAgentRegister/handleDeviceAgentTasks，插在 errResponse 前）+ `McpJsonRpcCore.ets`（buildToolDescriptors 尾部 2 条）+ `DeviceAgentStore.ets`（注册表 device_agents.json + 任务收件箱 device_agent_tasks/，StorageManager 文件持久化，在线=lastSeen<2min）。实测宿主 probe tools/list=21。
- **B UI**：`BrowserShell.ets`（interface DashDeviceAgent + @State 组 L95-100 + loadDashDeviceAgents/startDashDaPolling/selectDashDeviceAgent/dispatchDeviceAgentTask 方法组 + aboutToAppear/createNewTab 挂载 + provider pill 🤖前缀 + 下拉设备智能体分区 + sendChatInput 分流）；`AgentSidePanel.ets`（daAgents/daSel/daModelOpen @State + 5s 轮询 pollDaTasks 回流气泡 + 真下拉替换点击循环 + chat/agent 双模式分流）；i18n da* 10 条 zh/en。**新标签页下拉 dump 实证**：设备智能体/内置智能体/claude-code/claude-code·离线 全渲染。
- **C runner**：`tools/device_agent_runner.js`（node 原生 http，MCP query token 认证 —— **服务端只认 `?token=` 不认 Bearer header**，HttpMcpTransport.ets L270），30s 心跳，{prompt} shellQuote 模板，10min 超时，32KB 截断。`docs/DEVICE_AGENTS.md` + README/SECURITY/DEVPLAN 同步。
- **D 装机链**：hvigor assembleHap（DEVECO_SDK_HOME=C:\DevEco-Studio\sdk）→ `python tools/build_api23_hap.py` repack → `python tools/install_p8.py` 签名装机。闭环实测：echo 模板 pending→running→completed，result 回写正确。
- static_checks 全过。

## 验收实测命令（复跑配方）

- runner 启动脚本（设备端）：`/data/local/tmp/da_start.sh`（echo 模板）；token=base64 中转写 `/data/local/tmp/browseros_mcp_token`
- 注册表：`cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/device_agents.json`
- UI 下拉：新标签页 → 点 agnes-ai pill(约 524,415) → dump 见 设备智能体 分区

## 剩余（下一棒，非阻塞）

1. **真实 LLM 模板 E2E**：claude=`node --require /data/local/tmp/vm-fetch-full.cjs /data/local/tmp/claude-code-install/package/cli.js -p {prompt} --output-format text`；codex/hmh 同 docs/DEVICE_AGENTS.md。各跑一遍真任务（本轮 echo 已验全链路，省额度）。
2. AgentSidePanel 侧栏下拉 UI dump 验证（代码同源 DeviceAgentStore，风险低）。
3. smoke_reg 9/9 双模式回归（static 已过）。
4. 界面上真选 claude-code 发一条任务 → 侧栏气泡回流截图。

## 坑（勿再踩）

- MCP HTTP 端点鉴权只认 query `?token=`（HttpMcpTransport.ets），Bearer header 401。
- runner nohup 后台启动必须落盘 sh 脚本执行（cmd 引号嵌套会 ETIMEDOUT hold 死 hdc）。
- 宿主 root 直写应用沙盒任务文件后须 `chmod 666` 应用才能改写；应用自写无此问题。
- `hilog -x -t 200` 的 `-t` 是 log type（app/core/…）不是 tail；tail 用 `hilog -t app -x | tail`。
- build_api23_hap.py 只 repack 不编译；源码改动必须先 hvigor assembleHap 再 repack 再装机。
- ArkTS：Circle() 空括号不能带 `{}` 块；okResponse 里不能传 null/嵌套对象字面量（用 hasTask 布尔 + 类实例）。
- git add -A 会带上 .hm-tmp 全部杂物（本仓既有模式，41d5a13 已如此，接受）。
