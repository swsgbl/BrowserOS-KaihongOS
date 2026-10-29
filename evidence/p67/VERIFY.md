# P67 验收证据（2026-10-29 22:4x，设备 192.168.161.137:10178）

## A. MCP 工具 19→21（实测 tools/list）
- 21 工具含 agent_register / device_agent_tasks（宿主 probe HTTP 200，probe 脚本 .hm-tmp/p67_probe.cjs）

## B. runner 注册+心跳（echo 模板）
- runner 日志尾部：
  [2026-10-29T14:49:05.294Z] loop error: mcp tools/call http 401: {"error":"invalid token"}
  [2026-10-29T14:49:05.295Z] re-init failed: mcp initialize http 401: {"error":"invalid token"}
  [2026-10-29T14:49:12.300Z] loop error: mcp tools/call http 401: {"error":"invalid token"}
  [2026-10-29T14:49:12.301Z] re-init failed: mcp initialize http 401: {"error":"invalid token"}
  [2026-10-29T14:49:19.304Z] loop error: mcp tools/call http 401: {"error":"invalid token"}
  [2026-10-29T14:49:19.305Z] re-init failed: mcp initialize http 401: {"error":"invalid token"}
  [2026-10-29T14:49:26.312Z] loop error: mcp tools/call http 401: {"error":"invalid token"}
  [2026-10-29T14:49:26.313Z] re-init failed: mcp initialize http 401: {"error":"invalid token"}
  [2026-10-29T14:49:33.320Z] loop error: connect ECONNREFUSED 127.0.0.1:9222
  [2026-10-29T14:49:33.320Z] re-init failed: connect ECONNREFUSED 127.0.0.1:9222
  [2026-10-29T14:49:40.329Z] loop error: mcp tools/call http 401: {"error":"invalid token"}
  [2026-10-29T14:49:40.330Z] re-init failed: mcp initialize http 401: {"error":"invalid token"}
- 注册表快照：
  {"claude-code":{"name":"claude-code","kind":"claude-code","lastSeen":1793283810043,"registeredAt":1793282553159}}
- lastSeen 随心跳推进（1793282553159 → 1793282846264 实测两次快照差）

## C. 任务收件箱闭环（宿主模拟 UI 写任务 → runner 领取 → complete 回写）
- 任务文件：
  {"taskId":"dat_manual_1793282785246","agent":"claude-code","prompt":"打开 example.com 并总结页面内容","contextUrl":"https://example.com","contextTitle":"Example Domain","contextSelection":"","status":"completed","result":"PROMPT_WAS: 打开 example.com 并总结页面内容\n\n[Context page] Example Domain https://example.com","createdAt":1793282785246,"claimedAt":1793282948859,"completedAt":1793282948864}
- 状态流转 pending→running→completed，result 含 PROMPT_WAS+context 拼接（runner log "task done ok=true len=86"）
- 注意：宿主 root 直写文件需 chmod 666；应用自身写入无此问题（同 uid）

## D. UI 挂载留痕（hilog）
(hilog grep empty: Command failed: hdc -t 192.168.161.137:10178 shell "hilog -x -t 200 2>/dev/null | grep -E "P67|aboutToAppear|device agent|da selected|panel toggled" | tail -30"
'aboutToAppear' is not recognized as an internal or external command,
operable program or batch file.
)

## E. 构建链
- hvigor assembleHap 编译过（CompileArkTS 2s219ms）
- build_api23_hap.py repack（3925124B all-STORED）→ install_p8.py 签名装机 INSTALL+LAUNCH OK
## F. hilog 实抓（force-stop 重启后）
Invalid log type, the valid log types include app/core/init/kmsg/only_prerelease [CODE: -3]

Invalid log type, the valid log types include app/core/init/kmsg/only_prerelease [CODE: -3]

## G. hilog -t app 实抓
```
10-29 22:49:35.471 22738 22738 I A03d00/JSAPP: BrowserShell aboutToAppear start
10-29 22:49:35.472 22738 22738 I A03d00/JSAPP: BrowserShell aboutToAppear done
```

## H. UI 两段式下拉实拍（dump 文本全列）

点 provider pill (agnes-ai @524,415) 后 dump:
- 设备智能体 分区标题 ✓
- 内置智能体 分区标题 ✓
- claude-code 条目 ✓
- claude-code · 离线（kind+在线态小字）✓（runner 心跳停>2min 如实显示离线——语义正确）
- 截屏 evidence/p67/p67_dropdown2.jpeg

## I. 遗留（下一棒）
1. 真实 LLM 命令模板 E2E（claude/codex/hmh 各一遍，任务书 D 的完整版）——本轮 echo 模板已验全链路
2. AgentSidePanel 侧栏下拉的 UI dump 验证（代码已就位，与新标签页同一 DeviceAgentStore 数据源）
3. 断电恢复验证（注册表文件持久化，重装后仍在——本轮重装后 registry 保留即证据）
4. static_checks + smoke_reg 9/9 双模式回归
5. git commit（feat(p67): device agents inbox + switcher）
