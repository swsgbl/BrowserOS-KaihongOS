# P63 验证报告：敏感检测语义修正——FORM_SUBMIT 字面量档移除

日期: 2026-10-29 07:20-07:35 | 设备: 192.168.161.137:10178 | 开发: hmharness（wz3egw，无 final 中断，Zodex 接管收尾）| 验收: Zodex 独立复验

## 结论: PASS

## 裁决与依据（Zodex，P62 验收时立案）

`detectClick` 对选择器含 'form'/'submit' 子串返回 FORM_SUBMIT → 弹框等人确认。三重问题：①可绕过（同一按钮 `#su` vs `input[type=submit]`，字面量匹配=假安全）②打断最常见 agent 操作（搜索提交）③上游 BrowserOS 无任何工具级确认档。**裁决：删 FORM_SUBMIT 档，保留 PAYMENT/DELETE/SETTINGS 三档**（P51 验收清单要求的安全层）。

## 代码变更（hmh）

- `SensitiveOperationDetector.ets`：删 FORM_SUBMIT 规则 + 死代码（detectFormSubmit/isSensitive），保留三档关键词检测
- `SECURITY.md`：检测层重定位为"尽力而为的关键词层"（客户端无法语义保证、绕过原理可行、不应作唯一防线）+ FORM_SUBMIT 移除理由

## 验收（全部设备实测）

| 项 | 结果 | 证据 |
|---|------|------|
| **核心：p62_verify 5/5 @ sensitiveConfirm=true** | ✅（hmh run1 + Zodex 独立复跑双证） | A 探针 `input[type=submit]` 直接执行（click=ok，快照 5694→28332/28334 含 HarmonyOS 结果文本）——修复语义的直接证明 |
| 支付确认保持 | ✅ | PAY-nav 探针 15s 客户端超时（等确认挂起，未直接执行） |
| 表单导航直通 | ✅ | formsubmit URL 9ms 返回 |
| sensitiveConfirm=true 终态 | ✅ | 设备 config 实测（hmh 的 od 命令因 shell 引号失败，Zodex grep 复核） |
| static_checks | ✅ | 全过 |
| smoke_reg | 8/9 | 第 7 步 ⋮ 菜单按钮定位失败=**窗口化模式坐标漂移**（P40 期已知测试基建问题，与 P63 无关；hmh 已诊断 y=61 命中标题栏。转 P64 与 20 项回归整合修复） |

## 证据

evidence/p63/：p63_verify_run1.txt（hmh 5/5）· p63_pay_probe.txt（支付挂起+表单直通）· p63_smoke.txt（8/9 含漂移诊断）· VERIFY.md（本文件）

## 遗留

- smoke 第 7 步窗口化坐标漂移 → P64（测试基建，连同 P59-F 20 项回归整合）
- hmh 无 final 中断（第 9 次历史模式），收尾由 Zodex 接管
