# P62 续作状态（接续会话恢复现场用）

基线 git 8903a5f → 本轮工作区已含全部修复（未 commit）。目标设备 192.168.161.137:10178。

## 已完成（有实测证据）

- 六项修复全部落码并装机（两轮 build+sign+install 链全过）：
  - G: `BCPEngine.ets` click/type 改自包含同步表达式（不再依赖导航后即死的 `__bcp_arkts_callback` proxy）；`MCPServer.ets` callTool 加 30s 硬超时兜底（实测会返回明确 -32000 超时错误，app 不死）。
  - A(部分): `executeJS`/`evaluate` 加 Promise.race 超时（5s）；act click 成功后 `pageInfoAfterTransition` settle-poll 再返回。
  - B: read 快照为空/“null” 时返回显式 MCP_003 错误。
  - C: history back/forward 返回 `{url,title,action}`（实测 PASS，见 run2）。
  - D: grep 改用 SnapshotGenerator 同源（实测 hits=2 PASS）。
  - F: `tools/p59_regression.py:38` example.com 断言改为 documentation examples/文档示例。
- `static_checks` 全过；`smoke_reg` 9/9 PASS（证据 evidence/p62/ 下应有，若缺重跑）。
- `p62_verify` 两轮均 **4/5 PASS**（E/B/C/D 过，A 失败），证据 `evidence/p62/p62_verify_run2.txt`。

## A 项剩余问题（唯一未过项）

- 症状：`act click submit` 后 30s 服务端超时兜底触发（不再无界挂起——G 的验收已达标），但 click 内部的 executeJS race(5s) 没生效或 click 成功后的 `pageInfoAfterTransition` 内 `BCPEngine.evaluate` 悬死。hilog 无 P62/BCPEngine 标签日志（app 进程 14463 日志被系统噪音淹没）。
- 下一步诊断：给 executeJS timeout 分支加 `console.info('[P62] executeJS timeout ...')`、`pageInfoAfterTransition` 加阶段日志 → 重装 → 看 hilog 究竟卡在哪一层。怀疑点：①`unwrapSyncJson` 之前的 click 在 Baidu 上成功，进入 `pageInfoAfterTransition` 后 evaluate 的 race 没有真正短路（ArkTS `Promise.race` + `setTimeout` 在主线程阻塞时不触发？）②act handler 在 click 前还有 type_at 步骤耗时。
- 备选修复：`pageInfoAfterTransition` 不用 evaluate，改用 `webviewController.getUrl()`（IWebviewController 已有 getTitle，查 getUrl 是否存在——IWebviewController.ets:8 附近只有 getTitle，需确认）。或 click 后直接返回、依赖 5s executeJS race。
- 注意：A 探针链 = type_at(wd 框) + click(submit) + sleep4 + snapshot。click 前的 snapshot len=30069 both（Baidu 首页），type_at 后 click 超时。Baidu 搜索是同文档 SPA 转换——`pageInfoAfterTransition` 里 readyState 恒 complete、URL 稳定 500ms 即返回，不应超时 30s；故更可能卡在 click 的 executeJS 本身（Baidu 页面 runJavaScript 极慢/队列堆积？）。
- p62_verify A 探针输出线索：`len 30069->30069` —— before/after 快照**完全相同**（百度首页），导航实际**未发生**；after120 的 `<style data-for="result">` 是百度首页预载的结果页 CSS，非新文档。即 click(submit) 的效果没落地或没执行，且响应通道悬死至 30s 兜底。重点查：`handleAct` click 分支在 `BCPEngine.click(sel)` **之前**的 ref 解析/等待逻辑（sel 从哪来？是否 waitForElement/collectRefs 轮询卡住）——该函数体本轮未通读，是唯一盲区。

## 关键操作命令（复用）

- build: `cd /d "D:\BrowserOS - KaihongOS" && set DEVECO_SDK_HOME=C:\DevEco-Studio\sdk && call hvigorw assembleHap --mode module -p product=default --no-daemon`
- repack: `python tools\build_api23_hap.py`（输出 entry-api23-unsigned.hap，all-STORED）
- 装机: hdc file send → `sh /data/local/tmp/p62-sign-install.sh`（p57 脚本 s/p57/p62/ 生成，设备端 hap-sign-tool 签名+bm install+重启）
- token: `od -An -c .../files/mcp_token.txt`，宿主 fport 19222→9222 已建
- 验收: `node tools\p62_verify.cjs "http://127.0.0.1:19222/mcp?token=<T>"`
- 补丁脚本: `.hm-tmp\p62_patch.cjs`(1) `p62_patch2.cjs`(CRLF) `p62_patch3.cjs/3b`(编译错修复) `p62_patch4.cjs`(executeJS/evaluate race)

## 红线遵守情况

只改了 MCP 服务侧文件（BCPEngine.ets/MCPServer.ets）+ tools/p59_regression.py（F 断言）。ZIP_STORED 重打包已执行。static+smoke 已过。p62_verify 4/5（A 未过）。LLM 实测未做（A 修复后补）。
