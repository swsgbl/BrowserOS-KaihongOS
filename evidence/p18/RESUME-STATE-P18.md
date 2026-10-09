# P18 断点:侦查完毕,代码零写入(2026-10-09,上下文耗尽)

任务书:`.zcode/p18_brief.md`(搜索引擎注册表+设置切换+omnibox 引擎显示)。git 基点 1c53e8b(P17 收官)。限时 40 分钟收敛。

## 已确认的全部落点(照此写码,无需再读文件)

### A. 新文件 `entry/src/main/ets/common/SearchEngines.ets`
```ets
export class SearchEngine {
  id: string = ''; name: string = ''; queryUrl: string = ''; homeUrl: string = ''; desc: string = ''
  constructor(id: string, name: string, queryUrl: string, homeUrl: string, desc: string) { ... }
}
export const SEARCH_ENGINES: SearchEngine[] = [
  google  Google       https://www.google.com/search?q=            https://www.google.com
  bing    Bing         https://www.bing.com/search?q=             https://www.bing.com
  duckduckgo DuckDuckGo https://duckduckgo.com/?q=               https://duckduckgo.com
  baidu    百度         https://www.baidu.com/s?wd=               https://www.baidu.com
  sogou    搜狗         https://www.sogou.com/web?query=          https://www.sogou.com
  so360    360 搜索     https://www.so.com/s?q=                  https://www.so.com
  toutiao  头条搜索     https://so.toutiao.com/search?dvpf=pc&source=input&keyword=  https://so.toutiao.com
  yandex   Yandex      https://yandex.com/search/?text=           https://yandex.com
  brave    Brave Search https://search.brave.com/search?q=        https://search.brave.com
]
export function getEngineById(id: string): SearchEngine  // 未命中回退 google
```

### B1. `model/AppConfig.ets`
- AppConfigJSON + AppConfigUpdate 各加 `searchEngineId: string` / `searchEngineId?: string`
- class 字段 `searchEngineId: string = 'google'`;toJSON 加一行
- fromJSON 容错读(照 wsPort 模式,p13 注释):`config.searchEngineId = json['searchEngineId'] !== undefined && json['searchEngineId'] !== null ? json['searchEngineId'] as string : 'google'`

### B2. `storage/ConfigManager.ets`
- set() 加 `if (config.searchEngineId !== undefined) { this.config.searchEngineId = config.searchEngineId }`
- 加 `getSearchEngineId(): string { return this.config.searchEngineId }`

### B3. `pages/BrowserShell.ets` 行 1540(唯一改动点)
`this.navigate(Constants.DEFAULT_SEARCH_ENGINE + encodeURIComponent(input))` →
```ets
import { SearchEngines } from '../common/SearchEngines'  // 顶部
import { ConfigManager } from '../storage/ConfigManager'
const eng = SearchEngines.getEngineById(ConfigManager.getSearchEngineId())
this.navigate(eng.queryUrl + encodeURIComponent(input))   // Constants 保留兜底不删
```

### B4. `pages/SettingsPage.ets`(设置页搜索节)
- navItems 数组(现 5 项,ai/appearance/privacy/mcp/about)插入 `{ key: 'search', icon: $r('app.media.ic_search'), label: '搜索' }` 到 **ai 之前**(index 0),后续 navSelection 判断链(0/1/2/3/else)整体顺移——右侧内容 if 链加 `this.SearchSection()`
- 新 @Builder SearchSection():CardShell('搜索引擎','omnibox 输入非 URL 时使用的搜索引擎')+ 当前引擎行 + 弹层单选列表(ForEach SEARCH_ENGINES,每行 name+queryUrl 示例,选中行用 **ic_check**(已有,勿造新 svg),点击 → ConfigManager.update({searchEngineId: id}) + @State searchEngineId 刷新 + @State showEnginePicker 开关)
- aboutToAppear 初始化 `this.searchEngineId = ConfigManager.getSearchEngineId()`

### C. omnibox 引擎显示
- BrowserShell.updateSuggestions(~行1603):首行搜索项 title 直接拼引擎名(如 `Google 搜索 测试`),SuggestItem 结构不动 → ChromeWidgets 首行文本 `搜索 ${item.title}` 改为直接渲染 item.title(BrowserShell 侧拼好);组件底部加一行当前引擎标识+「切换」→ 新回调 onSwitchEngine,BrowserShell 接线 `router.pushUrl({url:'pages/SettingsPage', params:{'section':'search'}})`,SettingsPage.aboutToAppear 照 ViewSourcePage 行21 模式读 `router.getParams() as Record<string,Object>` 跳 navSelection
- 注意:BrowserShell onPick kind==='search' 走 onAddressInput(行315-316)已接好,不动

### 关键坑(历史教训)
- **媒体图标现状**:已有 ic_search/ic_check/ic_settings/ic_tab_search;**无 ic_radio/ic_done/ic_swap**——一律用现有图标,避免新增 svg 触发 v1 repack 资源同步坑(tools/p11_add_svgs_v1.py 三步)
- 同文件多 edit 并行=竞态覆盖,必串行
- uinput -K -t 只追加不清选区;hdc recv 须反斜杠路径
- baidu/so.com 直接 https 访问(任务书 D 节注)
- V1 链:.verify 无 build 脚本,真身在 **tools/**:build_v1_hap.py / install_p8.py / p11_add_svgs_v1.py

## 构建链(红线)
harmony build(build-profile.json5 在根)→ 若未动 resources 可跳 p11_add_svgs_v1 → `python tools/build_v1_hap.py` → `python tools/install_p8.py`(hdc 127.0.0.1:15566)。API≤14;ArkTS 严格;不重启 VM;不卸载包。

## D 节验证清单
1. 设置→搜索→切"百度"→omnibox 输"测试"回车 → dump 地址栏实证 `baidu.com/s?wd=` 且页面加载
2. 重启保持(config.json searchEngineId 持久化,可 hdc shell cat 沙盒 config.json)
3. 切回 Google 同验
4. 证据 evidence/p18/;commit `feat(p18): search engine registry + settings switcher + omnibus engine display`;DEVPLAN.md 追加 P18 节(照 P17 节格式)
