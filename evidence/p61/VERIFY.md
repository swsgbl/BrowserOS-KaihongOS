# P61 验证报告：VM 内驻 AI Agent 实测（本地 MCP 直连 + HOST LLM 中继）

日期: 2026-10-29 03:00-03:07 | 设备: 192.168.161.137:10178 (KaihongOS 6.1.2.08 PC / API23)

## 结论: PASS

首个**完全运行在 KaihongOS 设备内部**的 AI agent 自主驱动本机 BrowserOS 浏览器实测通过：
LLM 自主决策 → MCP loopback 直连执行 → 页面真实变化 → 读取真实内容 → 主动清理标签。

## 架构（实测通过）

```
VM (KaihongOS 192.168.161.137)              HOST (Windows 192.168.161.1)
━━━━━━━━━━━━━━━━━━━━━━              ━━━━━━━━━━━━━━━
vm_agent.js (Node.js v24.19.0)        llm_relay.js :19223
  ├─ MCP 工具执行 → 127.0.0.1:9222      └─→ https://apihub.agnes-ai.com
  │   (loopback 直连，无 fport 隧道)          (agnes-3.0-flash)
  └─ LLM 决策 → 192.168.161.1:19223
      (VMware NAT 网关到宿主机)
```

## 验证项

| # | 验证项 | 结果 | 证据 |
|---|--------|------|------|
| 1 | HOST 中继启动+转发 | ✅ | GET /health 200; LLM POST 200 |
| 2 | VM→HOST 中继连通 | ✅ | p61_net_test.js: VM_TO_HOST_RELAY_OK 200 |
| 3 | VM→MCP loopback 直连 | ✅ | GET /mcp → 405 POST-only（服务在线） |
| 4 | VM→中继→agnes LLM 往返 | ✅ | p61_llm_test.js: LLM_STATUS 200 回复"成功" |
| 5 | Agent 全循环·任务1 | ✅ | example.com: 5步14秒，正确标题+首段 |
| 6 | Agent 全循环·任务2 | ✅ | IANA: 7步，正确总结+标签数+主动关tab |
| 7 | Agent 全循环·任务3 交互控制 | ✅ 执行/🟡 读取 | baidu 搜索：type_at+click 真实生效（截图 URL=wd=上海天气+天气卡片）；snapshot 读到旧内容（bug 见下）+429 中止 |
| 8 | 浏览器页面真实变化 | ✅ | 截图×3 + uitest layout (URL=example.com) |
| 9 | MCP 服务端会话登记 | ✅ | hilog: [P51] session created client=vm-agent-p61 |
| 10 | P60 修复回归 | ✅ | hilog: notification accepted (202, empty body) |

## 任务1 详情（5 步 / 14 秒）

任务："打开 https://example.com 并告诉我页面标题和第一段内容"

LLM 决策链（agnes-3.0-flash，会话 429d91a7）:
1. `navigate example.com` → **-32000 "session owns no tab"**（P51 会话守卫拦截）
2. 自主改用 `tabs new` → tab_8 建立，页面加载
3. `snapshot` → 真实页面内容 (1054B)
4. `read` → 正文确认
5. 最终答案："页面标题为 Example Domain，第一段：该域名仅用于文档示例…" ✅

截图确认：浏览器地址栏与标签页显示 https://example.com/，页面已渲染。

## 任务2 详情（7 步）

任务："打开 https://www.iana.org/domains/reserved 并总结特殊用途域名，告诉我当前共几个标签页"

1. `tabs new` → IANA reserved domains 页 (tab_10)
2. `read` → **{"result":"null"}**（新建标签竞态，read 解析到活动标签）
3. **自主恢复**： `tabs activate tab_10`
4. `snapshot` → 真实 IANA 内容 (1587B)
5. `tabs list` → 4 个标签
6. `tabs close tab_10` → **主动清理**（系统提示 tidy up，与 P60 Claude Code 行为一致）
7. 最终答案：4 类特殊用途域名完整总结，11 个 IDN 测试 TLD 全部正确（测试 xn--0zwm56d 等），标签数推理正确 ✅

截图确认：IANA 标签已被 agent 关闭，剩 3 个标签，与 agent 回答一致。

## 任务3 详情（10 步，部分成功——交互控制实证 + 2 个新发现）

任务："打开 baidu.com，搜索框输入'上海天气'并搜索，告诉我天气信息"

1. navigate → 会话守卫 → `tabs new` (tab_11) → `navigate baidu.com` ✅
2. `act type_at input[name='wd'] "上海天气"` ✅ 执行成功
3. `act click input[type='submit']` ✅ 执行成功（耗时 9s）
4. `wait 2000` → `snapshot`/`read #content_left`/`read body`
5. **agnes 免费额度 429 限流**，中止

**截图铁证**：地址栏 = `https://www.baidu.com/s?wd=%E4%B8%8A%E6%B5%B7%E5%A4%A9%E6%B0%94`（wd=上海天气），页面显示上海天气卡片 —— **真实键盘输入+真实点击+真实表单提交全部生效**，这是首次实证 VM 内 agent 通过 act 工具完成交互式页面操作。

## 发现的问题

| 问题 | 影响 | 处置 |
|------|------|------|
| VM Node.js 全局 fetch 崩溃（WebAssembly is not defined） | undici 依赖 WASM，该构建未带 | agent 改用原生 http 模块（vm_agent.js 已内置） |
| `read` 在 tabs.new 后立即调用返回 `{"result":"null"}` | read 目标解析到活动标签而非会话新建标签 | 待 P62 修：read 默认会话最新 owned tab 或接受显式 tabId |
| **act 触发导航后 snapshot 返回旧页面内容**（任务3：搜索已提交、URL 已变，snapshot 仍返回首页 CSS 片段） | agent 无法读到交互后的结果页 | **P62 P1 项**：act/navigate 后 snapshot 缓存或 target 解析未失效 |
| agnes 免费档限流 429（本日 ~30 次请求后） | 长循环任务中断 | 中继可加退避重试；或升级 key |
| 控制台中文 mojibake | Windows GBK 终端显示问题，日志文件内容正常 | 无需修 |

## 证据文件

- `evidence/p61/p61_run1_log.json` — 任务1 agent 完整决策日志
- `evidence/p61/p61_run2_log.json` — 任务2 agent 完整决策日志
- `evidence/p61/p61_run3_log.json` — 任务3 agent 完整决策日志（交互控制）
- `evidence/p61/p61_run1_layout.json` — uitest dump（浏览器 URL=example.com）
- `evidence/p61/p61_run1b_screen.jpeg` — 浏览器前台截图（example.com 已加载）
- `evidence/p61/p61_run2_screen.jpeg` — 任务2后截图（IANA tab 已被 agent 关闭）
- `evidence/p61/p61_run3_screen.jpeg` — 任务3截图（baidu wd=上海天气 搜索结果+天气卡片）
- `evidence/p61/p61_hilog_mcp.txt` — 服务端 MCP RPC 全流水（53行：initialize/notify/tools/call）
- `tools/vm_agent.js` — VM 内驻 agent 脚本（已推送 /data/local/tmp/vm_agent.js）
- `tools/llm_relay.js` — HOST 中继脚本（node tools/llm_relay.js 启动）

## 意义

- 与 P60（HOST 上 Claude Code 经 fport 隧道）互补：本测试证明**设备本地 agent 生态可行**——浏览器无需宿主机隧道即可被同机 agent 控制，LLM 推理经最小中继出网
- P51 会话隔离（-32000 拦截无效导航）、P60 SDK 修复（202 空 body）在真实 agent 流量下回归通过
- agent 表现出错误恢复（任务1 会话守卫、任务2 read null）与整洁行为（主动关 tab）
