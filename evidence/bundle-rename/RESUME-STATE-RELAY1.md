# bundleName 更换任务断点（relay1，2026-10-06 上下文耗尽）

## 状态：侦查 100% 完成，代码 0 处改动（只读未写）。下棒直接从「执行清单」第 1 步开工。

## 红线（全程有效）
- 不碰 D:\oneaiterm；本线程 cwd 错误沿袭为 D:\oneaiterm，**所有命令必须先 `cd /d "D:\BrowserOS - KaihongOS"`**，写文件一律绝对路径指向 D:\BrowserOS - KaihongOS
- 不重启 VM/QEMU；不碰 hdc 127.0.0.1:5555；A1-A4 通过前不卸载 com.oneaiterm.terminal
- 目标新包名：`com.browseros.kaihong`；装机目标 hdc 127.0.0.1:15566

## 已核实事实（本棒实证）
1. **旧包名全部落点（源码+脚本+文档，缓存 .hvigor/entry/build 除外——反正步骤4会删）**：
   - `AppScope\app.json5:3` — `"bundleName": "com.oneaiterm.terminal"`
   - `deploy_hap.py:82` — `aa start -a EntryAbility -b com.oneaiterm.terminal`
   - `deploy_p1.py:73` — 同上
   - `DEVPLAN.md:21` — 装机流水线第 6 步 `aa start ... -b com.oneaiterm.terminal`（必须改）
   - `DEVPLAN.md:10` — bundleName 变更指令小节是历史指令描述（提及旧名作上下文），**保留不改**
   - entry\src\main\module.json5、全部 .ets 源码：**无**旧包名引用（findstr 实证）
   - p2_*.py 测试脚本：无旧包名（dir 列表已核对，findstr 未命中）
2. **app_name 双声明**：AppScope\resources\base\element\string.json 的 app_name="BrowserOS"（桌面名，保留）；entry\src\main\resources\base\element\string.json 也有 app_name="BrowserOS"（冗余，**删 entry 这条**，其 module.json5 用 EntryAbility_label 不受影响）。EntryAbility_label="BrowserOS" 无需动。
3. **bug-1 (llmBaseUrl 拼接) 相关文件已定位未深读**：
   - `model/AppConfig.ets` 行 20/35/57/79/104/128/129/131/132（128-132 疑似 merge/fromJSON 合并逻辑）
   - `storage/ConfigManager.ets` 行 73/74/105/106/118（保存/加载路径）
   - `service/AgentEngine.ets` 行 349/357/387；`pages/NeoDashboardPage.ets` 行 19/28/116/117/149/153/186（设置 UI）
   - 疑点方向：ConfigManager.save 或 AppConfig merge 处 append 而非 replace。下棒先读 ConfigManager.ets + AppConfig.ets 全文找拼接点。
4. **签名链**：流水线用 VM 内 hap-sign-tool + `/data/local/home/.ohos/signature/app1-profile-release.p7b`。p7b 内嵌 bundle-name 大概率= com.oneaiterm.terminal → 新包名装机预计报 9568325。处置：VM 上找 profile 源 JSON（同目录或 /data/local/home/.ohos/signature/ 附近，若只有 p7b 则用 hap-sign-tool 解包或直接手写 release-profile JSON：type=release, bundle-name=com.browseros.kaihong, distribution-certificate 用 OpenHarmonyApplication.pem 对应 issuer/serial——参考原 profile 内容），重新 `hap-sign-tool sign-profile` 生成新 p7b，再 sign-app。三件套：OpenHarmony.p12 / OpenHarmonyApplication.pem / app1-profile-release.p7b，密码 123456，keyAlias "OpenHarmony Application Release"。

## 执行清单（下棒按序）
1. 改 `AppScope\app.json5` bundleName → com.browseros.kaihong（edit_file 精确替换后复读验证——本仓库 edit_file 有静默失配前科，改完必须 findstr 复核）
2. `deploy_hap.py:82`、`deploy_p1.py:73` 的 `-b com.oneaiterm.terminal` → `-b com.browseros.kaihong`
3. `DEVPLAN.md:21` 流水线命令同步改新包名（第 10 行指令小节保留）
4. 删 entry string.json 中 app_name 条目（只留 AppScope 一处）
5. 清缓存：`rd /s /q entry\build` + `rd /s /q .hvigor` + `rd /s /q build`（若存在）
6. 构建：`cd /d "D:\BrowserOS - KaihongOS" && hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug`
7. API14 改包重打（照 deploy_hap.py / repack_hap.py 现有流程：module.json 三处版本改 14 + pack.info compatible/target=14 → zip 重打包）
8. 传送 + VM 内签名（先试旧 p7b；报 9568325 则按事实第 4 条重生成 profile）+ `bm install -p ... -r`
9. A1: `hdc shell bm dump -a | grep -E "oneaiterm|browseros"` 双包共存；A2: `aa start -a EntryAbility -b com.browseros.kaihong` + snapshot_display 截图回看进 BrowserShell；A3: 再 bm install -r 一次后 `bm dump -n com.oneaiterm.terminal` 仍在；A4: 全程零 uninstall。hilog 留证（`hilog -x | grep -i jsapp | tail -20`）
10. 修 bug-1：读 ConfigManager.ets/AppConfig.ets 定位拼接点 → 改整体替换 → 重走 6-8 装新包 → 设备 LLM 设置配 http://10.0.2.2:11434/v1 + qwen38:latest → 保存重进确认单一 URL（新包名=全新数据目录，需重新配置）
11. DEVPLAN.md 末尾追加汇报：改动文件清单/签名处理方式/A1-A4 判据原文/新包名/已知限制（旧应用数据不迁移）

## 已知坑
- edit_file 不可信：成功≠落盘，改完必 findstr/复读验证；关键文件用 node fs 或 python 精确替换(assert count==1)
- hdc 命令行记得用绝对路径 `"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"` 且 `-t 127.0.0.1:15566`
- 宿主壳把引号内复杂命令拒收时，落脚本文件再执行
- 装机验收前核对 build 日志时间晚于源码 mtime（HAR 内 so 预编译、install -r 不更新 installTime，设备常是旧包）
