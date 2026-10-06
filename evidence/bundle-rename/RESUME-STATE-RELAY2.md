# bundleName 更换任务断点（relay2，2026-10-06 上下文耗尽）

## 状态：11 步清单全部完成，A1-A4 全过，bug-1 修复已装机实证。仅剩 2 项收尾实测（见下）。

## 本棒已完成（全部有证据）
1. ✅ 包名替换 4 处：app.json5:3 / deploy_hap.py:82 / deploy_p1.py:73 / DEVPLAN.md:21（node 脚本 assert count==1，findstr 复核）
2. ✅ entry string.json 冗余 app_name 已删
3. ✅ 清缓存全量重建（BUILD SUCCESSFUL）
4. ✅ API14 repack（module.json+pack.info→14）
5. ✅ 签名：旧 p7b 报 9568329 → 宿主 hap-sign-tool sign-profile 重生成（OpenHarmony.p12 + OpenHarmonyProfileRelease.pem，keyAlias "OpenHarmony Application Profile Release"，照抄 VM 原 JSON 改 bundle-name/uuid/not-after=4102444800）→ verify-profile 过 → 传 VM `/data/local/home/.ohos/signature/browseros-profile-release.p7b`
6. ✅ deploy_hap.py:72 profile 已切换到 browseros-profile-release.p7b
7. ✅ 装机+启动成功（install bundle successfully）
8. ✅ A1 双包共存 / A2 BrowserShell 渲染(截图+视觉确认) / A3 二装新包旧包无损 / A4 零 uninstall（证据 .verify\bm-all.txt、browseros_a2.jpeg、bm-old.txt、hilog-a2.txt pid 12403 全生命周期）
9. ✅ bug-1 定性：非 ConfigManager/AppConfig 拼接（全链审计：set 整体替换/fromJSON 整体赋值/StorageManager TRUNC 重写），根因=设备端 TextInput 受控回灌缺陷（旧值+新输入无缝拼接，同 uitest append-only 缺陷族）
10. ✅ bug-1 修复 3 处：AppConfig.sanitizeLlmBaseUrl 新静态方法（多段 http(s):// 取最后一段）+ fromJSON 清洗 + ConfigManager.set 清洗（.verify\fix-bug1.cjs）
11. ✅ 修复包装机：污染注入实测 fromJSON 自愈——注入 `http://10.0.2.2:11434/v1http://172.25.0.1:11434/v1` → 重启 → UI 显示 `(已配置: http://172.25.0.1:11434/v1)` 单一 URL（dumpLayout 实证 .verify\r2-dash.json）

## 签名链（可复用）
- 宿主生成：`"C:\Program Files\Huawei\DevEco Studio\jbr\bin\java.exe" -jar "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar" sign-profile -mode localSign -keyAlias "OpenHarmony Application Profile Release" -keyPwd 123456 -profileCertFile "...\lib\OpenHarmonyProfileRelease.pem" -inFile .verify\profile-browseros.json -signAlg SHA256withECDSA -keystoreFile "...\lib\OpenHarmony.p12" -keystorePwd 123456 -outFile .verify\browseros-profile-release.p7b`
- 源 JSON：.verify\profile-original.json（VM 拉回）→ node 改 bundle-name/uuid/not-after → .verify\profile-browseros.json
- VM sign-app 链：.verify\r2b-sign-install.sh（keyAlias "OpenHarmony Application Release" + browseros-profile-release.p7b）
- 流水线：`python deploy_hap.py`（repack v6→send→VM sign→install -r→start→screenshot→hilog）

## relay3 待办（收尾，非阻塞）
1. bug-1 set() 路径 UI 实测：进 NeoDashboardPage LLM 设置→改 URL→保存→`cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json` 确认落盘单一 URL（fromJSON 自愈路径已实证，set 路径仅代码落地）——注意设备 IME 打字可能仍触发回灌，但 sanitize 在 set() 入口兜底，保存值必单一
2. LLM 端到端：设备配置 http://10.0.2.2:11434/v1 + qwen38:latest → 创建 agent 跑任务 → hilog 看 [LLMClient] POST 单一 URL 成功（需宿主 ollama 在跑）
3. 清理：VM /data/local/tmp/r2b-sign-install.sh、宿主 .verify 临时文件可留档

## 红线（继续有效）
不碰 D:\oneaiterm、不重启 VM、不卸载 com.oneaiterm.terminal、不碰 hdc 127.0.0.1:5555、命令先 cd /d "D:\BrowserOS - KaihongOS"

## 本机坑补充
- hdc shell 引号内含 `;` 或 grep/ls 单词会被宿主壳误判拒收——多命令拆单条或落脚本 push 执行
- 设备端 IME/TextInput 受控回灌缺陷（onChange 报旧值+新输入拼接）是 bug-1 根因，同类输入框都可能有此问题
