# P36 证据：Asset Store 真加密迁移 + 性能量化

日期：2026-10-18 | 设备：Quickemu KaihongOS VM 127.0.0.1:15566 | bundle: com.browseros.kaihong v1.1.0

## A. Asset 可用性结论（决定性证据：hilog_run1_mig.txt）

**KaihongOS 5.0 (API14) VM 上 @ohos.security.asset 服务可用**（SystemCapability.Security.Asset 存在）。

关键日志链（10:53 首启迁移会话, pid 11899）：
```
[P36] SecureStorageAdapter init: asset=true probe_ms=1315      ← 探活成功（冷 IPC 1.3s）
[P36] migrated llm_api_key to asset: sk-Z***THdt (51ch)        ← 明文 key 一次性迁入 asset（write 成功）
[P36] config.json rewritten without plaintext keys             ← 盘上脱敏完成
```

后续会话（probe 热路径）：
```
11:12:06 run2: asset=true probe_ms=7   load_ms=11
11:17:02 run3: asset=true probe_ms=8   load_ms=12
```

盘面核验（hdc cat config.json）：
```json
"llmApiKey":"" ← 脱敏后（迁移前为 sk-明文51字符）
```

## B. update 路径（代码级核验，未走 UI）

调用链：SettingsPage 保存按钮 → ConfigManager.update() → save() → syncKeysToAsset() →
SecureStorageAdapter.putSecret() → asset.add() / [24000003] → asset.update(query={ALIAS}, attrs={SECRET})。

实测修复记录：首次迁移后 update 曾报 401（attrs 误携 ALIAS），修复为 query/attrs 分离 Map
（SecureStorageAdapter.ets putSecret），修复后 11:12/11:17 会话无任何 asset fail 告警。
完整 UI 环验证（改 key→重启→回灌指纹日志）因 bm install -r 清 asset 数据未执行——
注：asset 条目随卸载/重装清除，属系统预期行为；迁移幂等性已实证（run2/run3 无重复迁移日志）。

## C. 性能数字（B 任务）

冷启动（EntryAbility.onCreate → BrowserShell aboutToAppear 完成收口点）：
```
run2: cold_start_ms=55   (probe_ms=7,  load_ms=11)
run3: cold_start_ms=60   (probe_ms=8,  load_ms=12)
```
注：VM 数值，含 2 标签页恢复；asset 探活热路径 <10ms，对冷启动增量可忽略
（探活是 query 探测别名，24000002=服务活）。对比：asset 探测引入前入口判定同步默认配置。

内存（hidumper --mem 24764，BrowserShell 运行态，2 tab + dashboard）：
```
主进程 PSS Total: 161071 KB (~157 MB)
渲染进程 com.browseros.kaihong:render pid 24838（独立统计）
```

## D. 入口页回归修复（P36 引入后修复）

asset 探活使 ConfigManager.load 变慢（冷 1.3s），onWindowStageCreate 的
onboardingCompleted 判定曾读到未加载默认值 → 误入 OnboardingPage。
修复：onCreate 持有 configReady promise，onWindowStageCreate await 后再判定
（EntryAbility.ets async 化 + return config）。run2/run3 已回 BrowserShell 正常。

## E. 文件清单（evidence/p36/）

- hilog_run1_mig.txt        迁移会话完整 hilog（asset=true/迁移/脱敏）
- hilog_run2_coldstart.txt  cold_start_ms=55 + BrowserShell 装载链
- hilog_run3_steady.txt     稳态复启 cold_start_ms=60 + 无重复迁移
- hidumper_mem.txt          PSS 161071 KB 完整表
- layout_browser_shell.json BrowserShell 运行态 UI 树（uitest dumpLayout）
- ui_shell.jpeg / s2_menu.jpeg  界面截图
