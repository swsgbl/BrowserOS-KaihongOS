# P62 final verdict（续跑轮）

## 根因（diag5-diag8 实证链）

A 残留的根因**不是** stale snapshot / 桥死亡，而是快照构建器本身：

- diag5：百度结果页完全正常（readyState=complete、innerText 3050 字符干净、桥函数全活），evaluate 全部拿到新鲜数据——但 snapshot/read 拿到 `<style data-for="result">` 开头的 30k CSS。
- diag8（决定性）：把与 `BCPEngine.snapshotMarkdown` 完全相同的构建器表达式走 evaluate（已证新鲜的路径）执行，digest 仍输出 `len=30008 head=<style data-for="result"...>`。
- 结论：百度结果页 DOM 里存在**字面嵌着 style 标签源码的文本节点**（第三方 SEO/注入产物）。旧构建器 clone body 后 walk 所有 textNode 取 textContent（263,834 字符），把这段 CSS 源码当正文吃进 md；而 `body.innerText`（spec：仅含已渲染文本）天然排除它（3050 字符干净）。iana 等简单页没有这种文本节点，所以只有"表单提交/百度结果页"复现——与导航方式无关。

## 修复（entry/src/main/ets/protocol/BCPEngine.ets）

`buildSnapshotMdExpr()` 重写为两层：

1. 文本骨架 = `document.body.innerText`（截 24000）——只含已渲染可见文本，style/script 载荷按 spec 排除。
2. 结构化元素（h1-h6/a/button+input[submit|button]/img/table）= `querySelectorAll` + computed-style 可见性过滤单独收集（链接≤200 条防刷屏）。

同时保留 [P62-A] 防线：payload 三重校验（可解析 {href,ready,md} / 非 raw-HTML 前缀且≥5 字符 / readyState settled）+ 3×700ms 重试——本次真凶修复后防线作为回归哨兵继续生效。

附带修复：`href.indexOf('http')!==0` 运算符优先级 bug（原 `!href.indexOf('http')===0` 恒 false，相对链接永不展开）。

## 验收结果（全绿）

| 项 | 结果 |
|---|---|
| node tools/p62_verify.cjs | **5/5 PASS**（A: click len 5796→28383 resultsHit=true） |
| 百度 e2e（type 上海天气 → click #su → wait 2s → read） | **PASS**：read len=25678(>1556) 天气=ture °C=true 无 CSS 污染；grep 天气 hits=46 |
| smoke_reg.py | **9/9 PASS**（重启清标签污染后；污染态 8/9 为诊断脚本遗留 tab 所致） |
| static_checks.py | all passed |
| sensitiveConfirm | **已恢复 true**（od dump 实证 config.json 落盘） |
| a-href 探针复验（true 态） | **A-FIX VERIFIED**（iana 3529→6359 fresh=true，href=/domains） |

证据文件：
- evidence/p62/p62_verify_run4.txt（5/5）
- evidence/p62/p62_acceptA_final.txt（百度 e2e PASS）
- evidence/p62/p62_afix_final.txt（a-href 探针 PASS，sensitiveConfirm=true 态）
- 诊断链脚本：.hm-tmp/p62_adiag5..8*.cjs

红线遵守：仅改 BCPEngine.ets（快照管线）；ZIP_STORED 重打包实证（all-STORED: True）；目标设备仅 192.168.161.137:10178。
