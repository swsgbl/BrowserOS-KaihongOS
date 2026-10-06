// Append P5 report to DEVPLAN.md (UTF-8)
const fs = require('fs');
const report = `
---

## P5 接线与打磨 汇报（2026-10-06 15:25 收棒）

### 做了什么
1. **Agent tab 渲染修复（P4 唯一遗留核心缺口）— 根因定位并修复，装机实证**
   - 排查路径：先疑事件链/ForEach，逐步排除——tab event 日志正常、@State 赋值正常（uiTabs=2）、两帧强制重建也执行（rebuild next frame: 2）但 UI 仍只 1 tab
   - **真根因：布局挤压**。tab item 的 Text 带 layoutWeight(1) 而外层 Row 无宽度约束，首个 tab 的 Text 吃满整行，后续 tab 被挤成 4px（uitest dumpLayout 实锤 Row [1371,235][1375,262]）。ForEach 从未失效
   - 修复：tab item Row 加 .layoutWeight(1)（.verify/p5_patch_lw.cjs，node 字节级补丁绕 CRLF）
   - 附带加固：covering 覆盖态标记 + tabsDirty 两帧重建（setTimeout 0），防覆盖态返回后同步残留
2. **装机流水线执行 3 轮**：hvigor build → p5_repack.py (API14) → p5_deploy.cjs（VM 侧 hap-sign-tool browseros-profile-release.p7b 签名 + bm install -r），均成功
3. **B 项接线现状确认**：书签☆/历史🕘按钮已在工具栏（书签 0 条·历史 0 条文案在）；ConfirmDialog 已挂 BrowserShell build() 消费 SENSITIVE_OPERATION_DETECTED；Onboarding 已有首帧路由逻辑（config onboardingCompleted=true，日志证实走 pages/BrowserShell）

### 验证了什么（装机后真实设备证据）
- ✅ 多标签渲染：about:blank + Dashboard + **Agent f8bhw5** 三标签并存，等分宽度（[503-823]/[849-1158]/[1195-1504]），点「+」立即新增 tab
- ✅ Agent tab 标题=代理名（Agent f8bhw5）
- ✅ 点 agent tab → Web 组件挂载：hilog 链 onControllerAttached tab_3 → registered webview adapter → onPageEnd(about:blank)；布局 dump Web 组件出现
- ❌ BCP 工具对活 agent 的端到端：**未完成**。时序竞态——agent 在 NeoDashboard 创建即开跑（~40s 跑完），点回 agent tab 时已结束，期间 BCP 全报 WebviewController must be associated with a Web component。需 agent 存活期间快速切 tab 重验（详见 evidence/p5/RESUME-STATE.md）

### 遗留什么（按优先级）
1. **BCP 端到端**（P4 核心缺口的最后一环）：agent 运行中点 agent tab → BCP navigate/getText/screenshot 成功 → sessions/*.json screenshots>0 → answer 含 Example Domain。修复本身可能不需要改码（Web 已挂上），是 e2e 时序问题；若切 tab 后 BCP 仍报错则查 BCPEngine.bindWebView 与 agent 运行循环的绑定时机
2. P5-3 Dashboard 激活异常复验：本轮三标签切换正常（about:blank/Dashboard/Agent 均可激活），Zodex 报告的旧异常疑已被本棒 covering/tabsDirty 修复覆盖，未专项复验
3. B4 回放入口（NeoDashboard 回放按钮→SessionPlayerPage 截图帧）：未动，依赖 BCP screenshots 非空
4. B5/B6 首启 Onboarding 与支付类 URL ConfirmDialog 触发：代码已在，未专项触发验证
5. C9 暗色主题：未动

### 工程状态
- 源码：entry/src/main/ets/pages/BrowserShell.ets（tab item layoutWeight + covering/tabsDirty）
- 构建：15:01 BUILD_OK → repack entry-p4-api14.hap (224641B, API14) → 已装机
- e2e 工具：.verify/p5_e2e.cjs（dump/inputs/clickxy/type/sleep）、p5_chain.cjs（BCP 链路日志）、p5_tabband2.cjs（tab 栏带状 dump）
- 断点文档：evidence/p5/RESUME-STATE.md
`;
fs.appendFileSync('DEVPLAN.md', report, 'utf8');
console.log('DEVPLAN appended, total bytes=' + fs.statSync('DEVPLAN.md').size);
