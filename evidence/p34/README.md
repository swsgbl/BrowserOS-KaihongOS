# P34 证据包：驾驶舱 hero 1:1 + UltrafastBanner + Skills 屏

日期：2026-10-17 · 设备：127.0.0.1:15566 (Quickemu VM, KaihongOS 5.0 API14)
构建链：hvigorw assembleHap → p11_add_svgs_v1.py → build_v1_hap.py → install_p8.py（VM 端签名）
产物：entry-p8-v1-unsigned.hap 736234 B（VM 签名后装机成功）

## 改动清单（P34 白名单内）

| 文件 | 改动 |
|---|---|
| entry/src/main/ets/components/NeoDashboardPanel.ets | E1 HeroCard 三段式 1:1（"What are your agents working on right now?"，working on 粗斜体 #7CB1FF/#1A73E8，产品名降级 12fp 角标）；E2 UltrafastBanner（ic_zap + Ultrafast mode + Request early access →/X，Preferences ultrafast_store: ultrafast_joined/ultrafast_dismissed 永久隐藏）；F SkillsTile 磁贴 |
| entry/src/main/ets/pages/SkillsPage.ets（新） | F Skills 屏：页头大标题+New skill、台账卡（Skill/Runs/Tokens saved/Run/Delete）、详情覆盖态、New skill 表单（name 自动补 /）、Delete 二次确认；Preferences skills_store: skills_v1 JSON；种子 3 条（/summarize-page /watch-price /fill-form）；Run=AgentEngine.createAgent(name, about:blank, prompt, ONCE)+runCount+1 落盘+AppStorage p34_skills_run_signal 信号+router.back |
| entry/src/main/resources/base/profile/main_pages.json | 注册 pages/SkillsPage |
| entry/src/main/ets/components/ChromeWidgets.ets | ThreeDotMenu group3 插入第 11 项 Skills（ic_robot） |
| entry/src/main/ets/pages/BrowserShell.ets | onMenuAction case 'skills' → router.pushUrl；@StorageLink('p34_skills_run_signal')+@Watch → showAgentPanel=true |
| entry/src/main/resources/base/media/ic_zap.svg（新） | 闪电图标（项目 + D:\v1tmp\final 双落盘，p11 final_ids 已加 57 条记录） |

并行约束遵守：未触碰 AgentSidePanel/AgentEngine/JSBridgeInjector/EntryAbility（P33 清单）。
注：P33 与本任务并行，main_pages.json 与 ChromeWidgets.ets 曾被 P33 重写覆盖本任务编辑，已重新合并（保留 P33 的 LlmHubPage 等条目）。

## 设备验证（全 PASS）

1. **E1 hero 1:1** — neo 面板截图 evidence/p34/neo_panel.jpeg：三段式英文标题渲染，working on 斜体蓝，产品名 12fp 角标。hilog: NeoDashboardPanel mounted。
2. **E2 banner** — evidence/p34/banner_joined.jpeg + hilog：
   - banner visible before: true
   - click CTA → join toast「已加入 Ultrafast 等待列表」+ 立即隐藏
   - 关闭重开 neo → 仍隐藏（joined=true 持久化，hilog: ultrafast banner state: joined=true dismissed=false hidden=true）
   - E2 ALL PASS
3. **F Skills 屏（磁贴入口）** — evidence/p34/skills_final3.jpeg：布局树全量确认 Skills 大标题/New skill/3 条种子/Runs/Tokens saved/Run/Delete 全渲染。AceRouter: creating page[2]: url: pages/SkillsPage + SkillsPage mounted + loaded 3 skills。
4. **F Skills 屏（⋮ 菜单入口）** — evidence/p34/menu_skills.jpeg：MENU->SKILLSPAGE: PASS。
5. **F Run 冒烟** — evidence/p34/run_smoke.jpeg + hilog：run skill: /summarize-page → skills run signal -> agent panel opened, signal=1 → skill agent created, runCount=1；router.back 返回 shell 且代理侧栏打开。
6. **F runCount 持久化** — evidence/p34/skills_runs1.jpeg：重进 SkillsPage 后 /summarize-page 行 Runs=1。RUNS_PERSISTED: PASS。

## 其它截图
- dashboard.jpeg：DashboardContent（P33 旧布局，非本任务范围）
- skills_page.jpeg / skills_page2.jpeg / skills_page_ok.jpeg：路由表缺失期间的中间态（调试过程）

## 排障记录
- 初次装机后 router 报 can't find this page pages/SkillsPage：V1 管线资源快照 D:\v1tmp\final 的 main_pages.json 未同步 + hvigor 产物被 P33 并行构建覆盖 → 同步 v1tmp + 重新注册 + 重建全链后恢复。
