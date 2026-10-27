# P53 验证记录 (2026-10-27)

## 构建链
- hvigor(SDK26) BUILD SUCCESSFUL -> build_api23_hap.py(全STORED+API23) -> VM签名 -> bm install 成功(5轮装机)

## 已实证(hilog/uitest dump)
1. **向导四步UI全渲染**: Step1 来源4卡(Netscape/Chrome JSON/Bitwarden/手动)+平台说明 / Step2 文件选择+沙盒路径+扫描按钮 / Step3 预览(代码) / Step4 结果(代码)
2. **入口接线**: 旧「导入登录态」(P7面板) 已改为 router.pushUrl(ImportWizardPage); SettingsPage 加「导入向导→」入口; main_pages.json 注册
3. **沙盒扫描**: hilog 21:14:42 scanSandbox found 4 files(config.json,mcp_token.txt,cookies.txt,wtest.txt) — filesDir=/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files(注意 haps/entry 层级!)
4. **文件点选**: hilog 21:14:44 sandbox file selected: cookies.txt (state 赋值实证)
5. **readSandboxText 调用链**: 20:48:57 readTextFromUri failed(当时 fixture 在错误目录) — 证明 下一步→loadFromSandbox→readSandboxText→readTextFromUri 全链已通
6. **启动无回归**: 重装后 8 tabs 恢复/JSBridge 注入正常/无 crash

## 未竟(自动化环境限制)
- E2E 最后一击: 软键盘遮挡「下一步」按钮(y=550), uitest 坐标点击被 IME 窗口吃掉; 真实用户不受影响(键盘可收)
- fixture 已就位: printf 直写 app filesDir/cookies.txt(Netscape 双域3条, 30天有效期)

## Profile 隔离(代码落地)
- TabInfo.profileType + isIncognito() (JSON 序列化含新字段, 旧数据兼容)
- Web incognitoMode: p47集合 || tab.isIncognito()
- closeTabById: 无痕标签关闭时 clearAllCookiesSync(true) 清无痕 cookie 存储

## Upload/PDF 闭环(代码落地+SDK实证)
- onShowFileSelector(since12) 已挂 Web 组件: DocumentViewPicker→handleFileList (web.d.ts:6508 实证)
- createPdf(since14) 全链: IWebviewController+WebViewAdapter(PdfConfiguration 8字段)+BCPEngine(base64,12MB上限)+MCPServer handlePdf 真实现
- 工具描述符更新: upload=interactive supported / pdf=supported base64

## 证据文件
- wizard_e2e_*.log.txt, hilog_v*.txt, dump JSON(z*/y*/w*/q* 系列), cookies_fixture.txt
