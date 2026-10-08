# P11-F 断点(RELAY4,2026-10-08 任务一完成,任务二未动工,上下文耗尽)

## 任务一已完成(本棒)
1. 工作树构建全绿:harmony_build(hvigor 1.1s)+ p11_add_svgs_v1.py(32 svg, ids 45 records 含 ic_search)+ build_v1_hap.py(Restool 5.0.1.011, 396226B)+ install_p8.py(VM 15566 签名装机 launch OK)
2. VM 截图实证:app 启动,书签条 3 pill(华为开发者/OpenHarmony/Example Domain)+ 全部书签 3 + dashboard hero 全渲染。图存 evidence/p11/p11f-boot.jpeg
3. 分笔提交:
   - 9a53886 feat(p11d) — BookmarkBar.ets 新建 + omnibox 分组下拉 + 书签气泡文件夹行 + BookmarkManager.load() 存量 bug 修复 + ic_search.svg + D/E 全部证据截图
   - 41c4b06 docs(p11) — DEVPLAN 追加 P11 节(A-E phase 映射+设备决策+证据索引+遗留)

## 任务二未动工(下棒直接开工)
### 停止按钮
- 代码现状(已勘察完):AddressBar.ets 的刷新按钮(行 ~46-59)= ic_reload,onClick 调 getActiveController()?.refresh()。
  改动落点:
  1. AddressBar 加 `@State isStopped: boolean` 或直接监听 isLoading 回调(父级传参 stopSignal: boolean)
  2. 加载中刷新图标 → ic_stop(需新建 SVG,复用现有 24x24 无 fill 属性规范,path 参考 M8 5v14h8V5H8z 或 Material stop 24px path M6 6h12v12H6z)
  3. 点击调 WebViewAdapter.stop() → 透传 webview.WebviewController.stop()(since 9,≤API14 已核对)
  4. IWebviewController.ets 加 `stop(): void` 接口方法
  5. 停止后 isLoading 归 false(onPageEnd 不会触发,需在 stop() 调用处手动复位状态)
- 构建链:同任务一(harmony_build → p11_add_svgs_v1.py → build_v1_hap.py → install_p8.py → 截图)

### 键盘拦截
- API 事实(已核对 SDK d.ts):
  - Web.onInterceptKeyEvent(callback: (event: KeyEvent) => boolean): WebAttribute — @since 9 ✅
  - Web.onInterceptKeyboardAttach(callback: WebKeyboardCallback): WebAttribute — @since 12 ✅
  - KeyEvent: @ohos.multimodal.input.event.KeyEvent(非 Web 专属,标准 OH keyevent)
- 组合键映射方案(浏览器标准):
  - Ctrl+L → 聚焦地址栏
  - Ctrl+R / F5 → 刷新
  - Ctrl+T → 新建标签页
  - Ctrl+W → 关闭当前标签
  - Ctrl+N → 新窗口(退化=新建标签页)
  - Ctrl+H → 历史
  - Ctrl+D → 加书签
- 实现落点:BrowserShell aboutToAppear 或 WebViewContent 的 Web().onInterceptKeyEvent
  返回 true=消费,false=透传给 Web。在 API14 实机验证 Ctrl 键组合是否被 OS 层拦截(KaihongOS 桌面有快捷键系统)
  若某组合 OS 层已占用则 DEVPLAN 如实记录 infeasible
- 注意:键盘事件在 WebView 内部会优先被 Web 页面消费,拦截时机=Web.onInterceptKeyEvent(页面 keydown 前)

### 下棒执行序
1. 写 stop() → IWebviewController + WebViewAdapter + AddressBar 图标切换
2. 写键盘拦截 → BrowserShell WebViewContent onInterceptKeyEvent
3. harmony_build → p11_add_svgs_v1.py(新建 ic_stop.svg)→ build_v1_hap.py → install_p8.py
4. VM 截图:p11f-stop.jpeg(加载中点击停止)+ p11f-keyboard.jpeg(键盘拦截生效)
5. git commit feat(p11f): 停止按钮 + 键盘拦截(Ctrl 组合)
6. DEVPLAN 更新 P11-F 节 + git commit docs(p11f)
