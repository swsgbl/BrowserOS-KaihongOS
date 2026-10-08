# P11-F 任务二断点(RELAY5, 2026-10-08)

## 任务二完成状态

### ① 停止按钮 — 已完成
- **ic_stop.svg** — 方形圆角停止图标（24×24, 1px 内缩），新增于 `resources/base/media/`
- **IWebviewController.ets** — 加 `stop(): void` 接口声明
- **WebViewAdapter.ets** — 加 `stop()` 透传实现（`this.controller.stop()`）
- **BrowserShell.ets** — 刷新按钮双态：`isLoading ? ic_stop : ic_reload`；
  加载中点击 → `stopActiveLoad()`（`controller.stop()` + 手动复位 `isLoading=false, loadProgress=0`）
- **构建绿** — hvigor BUILD SUCCESSFUL 5s；V1 repack 398460B；装机成功
- **截图** — `p11f-stop.jpeg`：非加载中时刷新箭头 ↻ 正确渲染

### ② 键盘快捷键 onInterceptKeyEvent — 代码已完成，实操未验证
- **API 实锤** — Web 组件 `onInterceptKeyEvent` 在 SDK14 `web.d.ts:7511`（since 9/11），
  API14 兼容；回调参数是 **ArkUI 通用 KeyEvent**（`common.d.ts:10147`），
  字段 `keyCode: number`（原生 Android 风格键码），**无 modifiers/key 对象**
- **键码** — KEYCODE_L=2028, KEYCODE_R=2034, KEYCODE_T=2036, KEYCODE_W=2039,
  KEYCODE_CTRL_LEFT=2072, KEYCODE_CTRL_RIGHT=2073（`@ohos.multimodalInput.keyCode.d.ts` 实测）
- **Ctrl 检测** — 用 `@State ctrlHeld` + 监听 Ctrl 键自身 Down/Up 事件，
  组合键到达时 `ctrlHeld===true` 才消费
- **KeyType 枚举不可导出** — `@kit.ArkUI` 无 `KeyType` export；用数值字面量
  `0=Down, 1=Up`（`enums.d.ts:2372`）
- **构建通过** — v3 补丁（`p11f_patch_v3.cjs`）移除 KeyType import，
  改用 `event.type === 0` / `event.type !== 0`
- **实操限制** — uinput 键盘注入在 VM 中 key 状态机卡死（key 28 未释放），
  无法注入 Ctrl+T/Ctrl+L 等组合键；与 RELAY3 记录一致（"键盘驱动 omnibox 导航不可用"）
- **截图** — `p11f-keyboard.jpeg`：uinput 注入后无 "KB Ctrl" hilog 日志，
  与 RELAY3 结论一致（Web 层 onInterceptKeyEvent 未收到 uinput 注入的按键事件）

### ③ 构建装机自测 — 已完成
- hvigor 构建 → V1 repack → 装机 → 启动 → 截图三张（stop/keyboard/boot）
- 停止按钮非加载态图标渲染正确
- 键盘快捷键：代码路径已编译通过，实操受 uinput 限制未达成

### ④ commit feat(p11f) — 待执行（本棒收尾）

## 文件变更清单
| 文件 | 变更 |
|------|------|
| `entry/src/main/resources/base/media/ic_stop.svg` | **新增** — 停止按钮 SVG |
| `entry/src/main/ets/common/IWebviewController.ets` | **改** — 加 `stop(): void` |
| `entry/src/main/ets/protocol/WebViewAdapter.ets` | **改** — 加 `stop()` 透传 |
| `entry/src/main/ets/pages/BrowserShell.ets` | **改** — 双态刷新按钮 + `stopActiveLoad()` + `onWebInterceptKeyEvent()` + `@State ctrlHeld` |

## 构建链
```
harmony_build (hvigor, BUILD SUCCESSFUL)
  → tools/p11_add_svgs_v1.py (33 svgs, ids 46)
  → tools/build_v1_hap.py (Restool 5.0.1.011, 398460B)
  → tools/install_p8.py (hap-sign-tool + bm install -r, INSTALL+LAUNCH OK)
```

## 红线核验
- tab item `.layoutWeight(1)` 未动 ✓
- 多 Web 常驻未动 ✓
- API ≤ 14 ✓（onInterceptKeyEvent since 9/11）
- 改码后先构建再 repack ✓

## 坑与教训
1. **Web KeyEvent ≠ @ohos.multimodalInput.keyEvent.KeyEvent** —
   Web 组件回调参数是 ArkUI 通用 KeyEvent（keyCode: number, type: KeyType），
   不是 multimodalInput 的 KeyEvent（key: Key, key.code: KeyCode）；
   字段名不匹配导致编译失败（Property 'key'/'modifiers' does not exist）
2. **KeyType 不可从 @kit.ArkUI 导出** — 用数值字面量 0/1
3. **uinput key 状态机卡死** — `hdc shell uinput -K -d 28` 后 key 28 永远显示
   "not release"，需 `bm uninstall` + 重装才重置；
   键盘路径验证需等 uinput 可用时补测

## 截图证据（evidence/p11/）
- `p11f-boot.jpeg` — 启动后 dashboard 状态
- `p11f-stop.jpeg` — 非加载中刷新按钮（↻ 图标正确渲染）
- `p11f-keyboard.jpeg` — uinput Ctrl+T 注入后（无效果，已知限制）
- `p11f-before.jpeg` — 桌面（非 app 前台，对照）

## 下棒（如继续）
- 键盘快捷键补测：需 uinput key 状态机重置（`bm uninstall com.browseros.kaihong` 后重装）
- 停止按钮补测：需导航到真实网页（`about:blank` 无法触发 `isLoading=true`）
