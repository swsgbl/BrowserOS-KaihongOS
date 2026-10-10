import { TabManager } from '../service/TabManager'
import { IWebviewController } from '../common/IWebviewController'
import { WebViewAdapter } from '../protocol/WebViewAdapter'
import { HistoryManager, HistoryEntry } from '../service/HistoryManager'
import { BookmarkManager } from '../service/BookmarkManager'
import { SensitiveOperationDetector } from '../service/SensitiveOperationDetector'
import { BCPEngine } from '../protocol/BCPEngine'
import { JSBridgeInjector } from '../protocol/JSBridgeInjector'
import { Constants } from '../common/Constants'
import { getEngineById } from '../common/SearchEngines'
import { ConfigManager } from '../storage/ConfigManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { TabStatus, SensitiveOperationType } from '../common/Types'
import { TabInfo } from '../model/TabInfo'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { NeoDashboardPanel } from '../components/NeoDashboardPanel'
import { webview } from '@kit.ArkWeb'
import { router } from '@kit.ArkUI'
import { LoginStateManager } from '../service/LoginStateManager'
import { ThreeDotMenu, OmniboxSuggestions, BookmarkBubble, SuggestItem } from '../components/ChromeWidgets'
import { AgentSidePanel } from '../components/AgentSidePanel'
import { TabStrip, TabSearchPanel } from '../components/TabStrip'
import { BookmarkBar } from '../components/BookmarkBar'
import { ContextMenu, CtxEntry, ctxDivider } from '../components/ContextMenu'
import { common } from '@kit.AbilityKit'
import { KeyCode } from '@kit.InputKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { Palette } from '../common/Palette'
import { DownloadManager, DownloadItem, DownloadStatus } from '../service/DownloadManager'

interface PageLoadErrorData {
  tabId: string
  error: string
}

interface PageLoadCompleteData {
  tabId: string
  url: string
}

/** P11d: 书签条条目(shell → BookmarkBar 传参) */
interface BarItem {
  id: string
  url: string
  title: string
}

@Entry
@Component
struct BrowserShell {
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') darkMode: boolean = false

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State currentUrl: string = ''
  @State urlInput: string = ''
  @State tabs: TabInfo[] = []
  @State activeTabId: string = ''
  @State isLoading: boolean = false
  @State ctrlHeld: boolean = false
  @State showDashboard: boolean = true
  @State loadProgress: number = 0
  // P17a: 导航错误横幅（主文档失败才置值；空=隐藏）
  @State navError: string = ''
  // P17a: onPageBegin 记录的主文档 URL（onErrorReceive 判定用，MCP/agent 导航不设 pendingUrl）
  private lastNavUrl: string = ''
  @State navErrorUrl: string = ''
  // P17c: 页内查找条
  @State showFindBar: boolean = false
  @State findQuery: string = ''
  @State findStatus: string = ''
  @State isBookmarked: boolean = false
  // P9-A: chrome 补全 —— ⋮ 菜单 / omnibox 建议 / 书签气泡
  @State showMenu: boolean = false
  @State showSuggestions: boolean = false
  @State suggestItems: SuggestItem[] = []
  @State showBookmarkBubble: boolean = false
  @State bookmarkBubbleTitle: string = ''
  @State bookmarkBubbleUrl: string = ''
  @State bookmarkBubbleExisting: boolean = false
  // P9-B: Agent 侧栏
  @State showAgentPanel: boolean = false
  // P6: NeoDashboard 内嵌覆盖层（不再 router.pushUrl，规避覆盖态不渲染）
  @State showNeo: boolean = false
  // 每个 Tab 独立的 WebviewController（key=tabId）
  private controllers: Map<string, webview.WebviewController> = new Map()
  private pendingUrl: string = ''
  private pendingUrlTab: string = ''
  // P16b: session restore URL (tabId->url), consumed by onControllerAttached
  private restoreUrlMap: Map<string, string> = new Map()
  // P5: 覆盖态（NeoDashboard 前台）@State 赋值不驱动渲染；返回时需强制 ForEach 重建
  private tabsDirty: boolean = false
  /** P5: 覆盖态标记 —— NeoDashboardPage/Onboarding 覆盖时 BrowserShell 不可见 */
  private covering: boolean = false
  private attachedTabs: Set<string> = new Set()
  /** P19c: 站点权限请求弹层 —— origin + 资源列表 + 待决 request */
  @State permOrigin: string = ''
  @State permKinds: string = ''
  private pendingPermReq: PermissionRequest | null = null

  /** P19c: ProtectedResourceType -> 中文说明 */
  private permResLabel(res: string): string {
    if (res.includes('VIDEO')) {
      return '摄像头'
    }
    if (res.includes('AUDIO')) {
      return '麦克风'
    }
    if (res.includes('MIDI')) {
      return 'MIDI 设备'
    }
    if (res.includes('SENSOR')) {
      return '运动传感器'
    }
    return '设备资源'
  }

  /** P19c: 权限弹层显隐 */
  private showPermDialog(origin: string, resources: string[], req: PermissionRequest): void {
    this.permOrigin = origin
    this.permKinds = resources.map((r: string) => this.permResLabel(r)).join('、')
    this.pendingPermReq = req
    console.info('P19c perm dialog: origin=' + origin + ' res=' + resources.join(','))
  }

  private grantPerm(allow: boolean): void {
    const req = this.pendingPermReq
    if (req) {
      if (allow) {
        const res = req.getAccessibleResource()
        req.grant(res)
        console.info('P19c perm GRANT: ' + this.permOrigin + ' res=' + res.join(','))
      } else {
        req.deny()
        console.info('P19c perm DENY: ' + this.permOrigin)
      }
    }
    this.pendingPermReq = null
    this.permOrigin = ''
    this.permKinds = ''
  }

  aboutToAppear(): void {
    console.info('BrowserShell aboutToAppear start')
    // P14b: 书签变更订阅驱动刷新
    EventBus.on(EventBusEvents.BOOKMARKS_CHANGED, this.onBookmarksChanged)
    EventBus.on(EventBusEvents.HISTORY_CHANGED, this.onHistoryChanged)
    this.refreshCounts()
    // P11d: 书签持久化加载(此前无人调用 load —— 存量 bug,重启即丢)
    BookmarkManager.load().then(() => {
      this.refreshBookmarkState()
      this.refreshCounts()
      console.info('BrowserShell bookmarks loaded: ' + BookmarkManager.getBookmarkCount())
    }).catch((e: Object) => {
      console.error('BrowserShell bookmark load fail: ' + e)
    })
    try {
      this.tabs = TabManager.getAllTabs()
      console.info('BrowserShell tabs loaded: ' + this.tabs.length)
      // P16b: 会话恢复 URL 补载 —— restoreTabs 重建的标签 URL 存入 map，
      // onControllerAttached（每个常驻 Web 均触发）按 tabId 消费 loadUrl
      const restoreUrls = TabManager.takeRestoreUrls()
      for (const ru of restoreUrls) {
        this.restoreUrlMap.set(ru.tabId, ru.url)
        console.info('BrowserShell restore url pending: ' + ru.url + ' tab=' + ru.tabId)
      }
      if (this.tabs.length === 0) {
        const tab = TabManager.createTab(true)
        this.tabs = [tab]
        this.activeTabId = tab.tabId
        this.showDashboard = true
        console.info('BrowserShell created tab: ' + tab.tabId)
      } else {
        this.activeTabId = TabManager.getActiveTabId()
        const activeTab = TabManager.getTab(this.activeTabId)
        this.showDashboard = activeTab?.isDashboard ?? true
        console.info('BrowserShell active tab: ' + this.activeTabId)
      }
      EventBus.on(EventBusEvents.TAB_STATUS_CHANGE, this.onTabStatusChange)
      console.info('BrowserShell aboutToAppear done')
    } catch (e) {
      console.error('BrowserShell aboutToAppear error: ' + e)
    }
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.TAB_STATUS_CHANGE, this.onTabStatusChange)
    EventBus.off(EventBusEvents.BOOKMARKS_CHANGED, this.onBookmarksChanged)
    EventBus.off(EventBusEvents.HISTORY_CHANGED, this.onHistoryChanged)
    EventBus.off(EventBusEvents.DOWNLOAD_CHANGED, this.onDownloadChanged)
  }

  /** P5: 页面回到前台（router.back 从 NeoDashboard 返回）时强制重同步标签栏
   *  —— 修复 agent tab 创建于覆盖态时标签栏不渲染的 P4 遗留 */
  onPageShow(): void {
    console.info('BrowserShell onPageShow: resync tab state')
    this.covering = false
    this.syncFromTabManager()
  }

  onPageHide(): void {
    console.info('BrowserShell onPageHide: entering cover state')
    this.covering = true
  }

  private syncFromTabManager(): void {
    try {
      const all = TabManager.getAllTabs()
      console.info('BrowserShell sync: managerTabs=' + all.length + ' uiTabs=' + this.tabs.length + ' active=' + TabManager.getActiveTabId() + ' dirty=' + this.tabsDirty)
      if (this.tabsDirty) {
        // 覆盖态期间 tab 集合变化过：同帧 []→all 两次赋值被 ArkUI 批合并，
        // ForEach 子树未销毁。必须两帧：本帧清空销毁，下一帧全量重建
        this.tabs = []
        this.tabsDirty = false
        setTimeout(() => {
          this.tabs = TabManager.getAllTabs()
          const activeId2 = TabManager.getActiveTabId()
          if (activeId2.length > 0) {
            this.activeTabId = activeId2
          }
          console.info('BrowserShell rebuild tabs next frame: ' + this.tabs.length)
        }, 0)
        return
      }
      this.tabs = all
      const activeId = TabManager.getActiveTabId()
      if (activeId.length > 0) {
        this.activeTabId = activeId
      }
      const activeTab = TabManager.getTab(this.activeTabId)
      if (activeTab) {
        this.showDashboard = activeTab.isDashboard
        if (activeTab.currentUrl) {
          this.urlInput = activeTab.currentUrl
          this.currentUrl = activeTab.currentUrl
          this.refreshBookmarkState()
        }
      }
    } catch (e) {
      console.error('BrowserShell syncFromTabManager error: ' + e)
    }
  }

  private onTabStatusChange = (data: Object): void => {
    try {
      // P5: 全量同步（tabs + activeTabId + showDashboard），修复 UI 激活态与
      // TabManager 脱节（"点 Dashboard 后 about:blank tab 仍激活"的根因）
      const allTabs = TabManager.getAllTabs()
      if (allTabs.length !== this.tabs.length) {
        this.tabsDirty = true
      }
      // P5: 覆盖态（NeoDashboardPage 前台）期间 BrowserShell @State 赋值不驱动渲染，
      // 标记 dirty 让 onPageShow 返回时强制两帧重建
      if (this.covering) this.tabsDirty = true
      console.info('BrowserShell tab event: managerTabs=' + allTabs.length + ' uiTabs=' + this.tabs.length + ' dirty=' + this.tabsDirty)
      this.tabs = allTabs
      const activeId = TabManager.getActiveTabId()
      if (activeId.length > 0 && activeId !== this.activeTabId) {
        this.activeTabId = activeId
        const tab = TabManager.getTab(activeId)
        this.showDashboard = tab ? tab.isDashboard : this.showDashboard
        this.urlInput = tab && tab.currentUrl ? tab.currentUrl : this.urlInput
      }
    } catch (e) {
      console.error('BrowserShell onTabStatusChange error: ' + e)
    }
  }

  /** P14b: 书签订阅（BookmarkManager 增删改广播 → 星标/书签条即时刷新，免手动 load） */
  private onBookmarksChanged = (data: Object): void => {
    this.refreshBookmarkState()
    console.info('BrowserShell bookmarks-changed -> bar refreshed')
  }

  /** R5: 计数刷新（书签直读 + 历史镜像长度） */
  private refreshCounts(): void {
    this.bookmarkCount = BookmarkManager.getBookmarkCount()
    this.historyCount = HistoryManager.getAllHistory(500).length
  }

  private refreshBookmarkState(): void {
    this.isBookmarked = this.currentUrl.length > 0 && BookmarkManager.isBookmarked(this.currentUrl)
    // P11d: 书签条数据同步(createdAt 降序由 getAllBookmarks 保证)
    this.bookmarkBarItems = BookmarkManager.getAllBookmarks().map((b): BarItem => {
      return { id: b.id, url: b.url, title: b.title }
    })
  }

  build(): void {
    Stack() {
      Column() {
        // P22: Chromium 布局顺序 —— 标签条最顶、工具栏其下（此前 AddressBar 在上，与原生颠倒）
        this.TabBar()
        this.AddressBar()
        // P11d: 书签条 —— 仅新标签页(dashboard)/驾驶舱(neo)显示
        if (this.showDashboard || this.showNeo) {
          BookmarkBar({
            bookmarks: this.bookmarkBarItems,
            onOpenBookmark: (url: string) => {
              console.info('BrowserShell bookmark-bar open: ' + url)
              // P11d: 当前标签直接导航(Chromium 行为:书签条点击=当前标签跳转)
              this.navigate(url)
            }
          })
        }
      // P6 治本：Web 层常驻 —— 所有 tab 的 Web 组件始终挂载（非激活 Hidden 保活），
      // dashboard/NeoDashboard 作为覆盖层置顶。修复「dashboard 激活时全部 Web 销毁、
      // 覆盖态 ForEach 不新增」的时序缺口：agent tab 创建即有 WebView，BCP 立即可用。
      // P21: 上游 chrome.sidePanel 停靠语义 —— 工具栏/标签条横贯窗口顶部，
      // 面板停靠内容区右侧与页面并排（此前为根 Stack 浮层覆盖工具栏，视觉似独立窗口）
      Row() {
      Stack({ alignContent: Alignment.Top }) {
        this.WebViewContent()
        this.ErrorBanner()
        this.FindBar()
        if (this.showDashboard) {
          this.DashboardContent()
        }
        if (this.showNeo) {
          NeoDashboardPanel({
            shellBack: () => {
              console.info('BrowserShell neo panel closed')
              this.showNeo = false
            },
            shellOpenReplay: (sessionId: string) => {
              console.info('BrowserShell open replay: ' + sessionId)
              this.showNeo = false
              const navParams: Record<string, Object> = { 'sessionId': sessionId }
              router.pushUrl({ url: 'pages/SessionPlayerPage', params: navParams })
            }
          })
        }
      }
      .layoutWeight(1)
      if (this.showAgentPanel) {
        Column() {
          AgentSidePanel({
            onClose: () => {
              console.info('BrowserShell agent panel closed')
              this.showAgentPanel = false
            }
          })
        }
        .width(360)
        .height('100%')
        .backgroundColor(this.pal().surfaceAlt)
        .border({ width: { left: 1 }, color: this.pal().border }) // P21b: hairline divider replaces heavy shadow (upstream style)
      }
      }
      .layoutWeight(1)
      // P5: 敏感操作确认对话框（自监听 SENSITIVE_OPERATION_DETECTED）
      ConfirmDialog({
        onConfirm: (agentId: string, operationType: SensitiveOperationType) => {
          console.info('BrowserShell ConfirmDialog onConfirm agent=' + agentId)
          SensitiveOperationDetector.confirmOperation(agentId, operationType)
        },
        onReject: (agentId: string, operationType: SensitiveOperationType) => {
          console.info('BrowserShell ConfirmDialog onReject agent=' + agentId)
          SensitiveOperationDetector.rejectOperation(agentId, operationType)
        }
      })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().surface)

      // P9-A: chrome 覆盖层（挂 build 根 Stack，置顶不参与布局流）
      if (this.showSuggestions) {
        OmniboxSuggestions({
          items: this.suggestItems,
          engineName: getEngineById(ConfigManager.getSearchEngineId()).name,
          onSwitchEngine: () => {
            console.info('BrowserShell switch engine entry')
            this.showSuggestions = false
            const navParams: Record<string, Object> = { 'section': 'search' }
            router.pushUrl({ url: 'pages/SettingsPage', params: navParams })
          },
          onPick: (kind: string, url: string) => {
            console.info('BrowserShell suggestion picked: kind=' + kind + ' url=' + url)
            this.showSuggestions = false
            if (kind === 'search') {
              // P11d: 搜索项 —— 走 onAddressInput 的搜索引擎 fallback
              this.onAddressInput(url)
            } else {
              this.navigate(this.normalizeUrl(url))
            }
          },
          onClose: () => {
            this.showSuggestions = false
          }
        })
      }
      if (this.showBookmarkBubble) {
        BookmarkBubble({
          title: this.bookmarkBubbleTitle,
          url: this.bookmarkBubbleUrl,
          editingExisting: this.bookmarkBubbleExisting,
          onTitleChange: (title: string) => {
            this.bookmarkBubbleTitle = title
          },
          onDone: () => {
            this.finishBookmarkEdit()
          },
          onRemove: () => {
            this.removeCurrentBookmark()
          },
          onClose: () => {
            this.showBookmarkBubble = false
          }
        })
      }
      if (this.showTabSearch) {
        TabSearchPanel({
          tabs: this.tabs,
          activeTabId: this.activeTabId,
          onPick: (tabId: string) => {
            this.showTabSearch = false
            TabManager.switchTab(tabId)
            this.activeTabId = tabId
            const tab = TabManager.getTab(tabId)
            this.showDashboard = tab ? tab.isDashboard : false
          },
          onCloseTab: (tabId: string) => {
            this.closeTabById(tabId)
          },
          onCreate: () => {
            this.showTabSearch = false
            this.createNewTab()
          },
          onClose: () => {
            this.showTabSearch = false
          }
        })
      }
      if (this.ctxMenuX >= 0) {
        ContextMenu({
          x: this.ctxMenuX,
          y: this.ctxMenuY,
          entries: this.ctxEntries,
          onClose: () => {
            this.ctxMenuX = -1
          }
        })
      }
      if (this.showMenu) {
        ThreeDotMenu({
          onAction: (action: string) => {
            this.onMenuAction(action)
          },
          onClose: () => {
            this.showMenu = false
          }
        })
      }
      // P19c: 站点权限请求弹层
      if (this.permOrigin.length > 0) {
        Column()
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.grantPerm(false)
        })

        Column() {
          Text(this.permOrigin)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('想要使用' + this.permKinds)
            .fontSize(13)
            .fontColor(this.pal().text)
            .margin({ top: 8 })
          Text('允许后该站点可在你使用浏览器时访问' + this.permKinds + '。')
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 6 })
            .textAlign(TextAlign.Center)
          Row({ space: 10 }) {
            Button('阻止')
              .fontSize(13)
              .height(34)
              .layoutWeight(1)
              .backgroundColor(this.pal().surfaceAlt)
              .fontColor(this.pal().text)
              .onClick(() => {
                this.grantPerm(false)
              })
            Button('允许')
              .fontSize(13)
              .height(34)
              .layoutWeight(1)
              .backgroundColor('#1A73E8')
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.grantPerm(true)
              })
          }
          .width('100%')
          .margin({ top: 16 })
        }
        .width('76%')
        .padding(20)
        .borderRadius(14)
        .backgroundColor(this.pal().surface)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AddressBar(): void {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_back'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .accessibilityText('后退')
      .onClick(() => {
        console.info('BrowserShell back button clicked, tabId=' + this.activeTabId)
        const controller = this.getActiveController()
        if (controller && controller.accessBackward()) {
          console.info('BrowserShell BACK -> controller.backward() on tabId=' + this.activeTabId)
          controller.backward()
        } else {
          console.info('BrowserShell BACK skipped: no backward history, tabId=' + this.activeTabId)
        }
      })

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_forward'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .accessibilityText('前进')
      .onClick(() => {
        console.info('BrowserShell forward button clicked, tabId=' + this.activeTabId)
        const controller = this.getActiveController()
        if (controller && controller.accessForward()) {
          console.info('BrowserShell FORWARD -> controller.forward() on tabId=' + this.activeTabId)
          controller.forward()
        } else {
          console.info('BrowserShell FORWARD skipped: no forward history, tabId=' + this.activeTabId)
        }
      })

      // P11f: 加载中刷新钮变停止钮(点它即 stop)
      Button({ type: ButtonType.Normal }) {
        Image(this.isLoading ? $r('app.media.ic_stop') : $r('app.media.ic_reload'))
          .width(20).height(20)
          .fillColor(this.isLoading ? '#1A73E8' : this.pal().text2)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.isLoading ? '停止加载' : '刷新')
      .onClick(() => {
        if (this.isLoading) {
          this.stopActiveLoad()
        } else {
          console.info('BrowserShell refresh button clicked, tabId=' + this.activeTabId)
          const controller = this.getActiveController()
          if (controller) {
            console.info('BrowserShell REFRESH -> controller.refresh() on tabId=' + this.activeTabId)
            this.isLoading = true
            controller.refresh()
          } else {
            console.info('BrowserShell REFRESH skipped: controller not attached, tabId=' + this.activeTabId)
          }
        }
      })

      // P9-A: omnibox —— 安全锁图标（https 绿锁 / 普通灰）+ 输入框胶囊
      Row() {
        Image(this.currentUrl.startsWith('https://') ? $r('app.media.ic_lock') : $r('app.media.ic_info'))
          .width(16).height(16)
          .fillColor(this.currentUrl.startsWith('https://') ? '#137333' : '#5F6368')
          .draggable(false)
        TextInput({ text: this.urlInput, placeholder: '输入URL或搜索关键词' }).id('p11f_omnibox').fontColor(this.pal().text).placeholderColor(this.pal().text2)
          .layoutWeight(1)
          .height(32)
          .fontSize(13)
          .type(InputType.Normal)
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0 })
          .onChange((value: string) => {
            this.urlInput = value
            this.updateSuggestions(value)
          })
          .onFocus(() => {
            this.updateSuggestions(this.urlInput)
            this.showSuggestions = this.suggestItems.length > 0
          })
          .onBlur(() => {
            // 延迟关闭：给建议项点击留出事件窗口
            setTimeout(() => {
              this.showSuggestions = false
            }, 150)
          })
          .onSubmit(() => {
            this.showSuggestions = false
            this.onAddressInput(this.urlInput)
          })
      }
      .layoutWeight(1)
      .height(34)
      .padding({ left: 8, right: 8 })
      .borderRadius(17)
      .backgroundColor(this.pal().surface)
      .border({ width: 1, color: this.pal().border })

      if (this.isLoading) {
        Text(`${this.loadProgress}%`)
          .fontSize(12)
          .fontColor('#007DFF')
          .margin({ left: 4 })
      }

      // P11a: 星标（SVG 双态染色）—— 点击弹 Bookmark 气泡（名称编辑+完成/删除）
      Button({ type: ButtonType.Normal }) {
        Image(this.isBookmarked ? $r('app.media.ic_star_filled') : $r('app.media.ic_star_outline'))
          .width(20).height(20)
          .fillColor(this.isBookmarked ? '#F9AB00' : '#5F6368')
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.isBookmarked ? '编辑书签' : '添加书签')
      .onClick(() => {
        this.openBookmarkBubble()
      })

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_history'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .accessibilityText('历史记录')
      .onClick(() => {
        // P22: 统一历史入口 —— 工具栏与 ⋮ 菜单同走 Chromium 风格路由页（旧内嵌面板删除）
        router.pushUrl({ url: 'pages/HistoryPage' })
      })

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_home'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .accessibilityText('回到主页')
      .onClick(() => {
        this.goHome()
      })

      // P9-B: Agent 侧栏切换按钮
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_agent'))
          .width(20).height(20)
          .fillColor(this.showAgentPanel ? '#1A73E8' : '#5F6368')
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .accessibilityText('AI 代理侧栏')
      .onClick(() => {
        console.info('BrowserShell agent panel toggled: ' + !this.showAgentPanel)
        this.showAgentPanel = !this.showAgentPanel
      })

      // P9-A: ⋮ 三点主菜单
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_more_vert'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .accessibilityText('主菜单')
      .onClick(() => {
        console.info('BrowserShell three-dot menu toggled: ' + !this.showMenu)
        this.showMenu = !this.showMenu
      })
    }
    .width('100%')
    .height(48)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.pal().surfaceAlt)
  }

  /** P5: 书签切换（BookmarkManager 接线） */
  private toggleBookmark(): void {
    if (this.currentUrl.length === 0) {
      console.info('BrowserShell bookmark skipped: no url')
      return
    }
    if (BookmarkManager.isBookmarked(this.currentUrl)) {
      const id = BookmarkManager.getBookmarkIdByUrl(this.currentUrl)
      if (id) {
        BookmarkManager.removeBookmark(id)
        console.info('BrowserShell bookmark removed: ' + this.currentUrl)
      }
    } else {
      const tab = TabManager.getTab(this.activeTabId)
      const title = tab && tab.title ? tab.title : this.currentUrl
      BookmarkManager.addBookmark(this.currentUrl, title)
      console.info('BrowserShell bookmark added: ' + this.currentUrl + ' title=' + title)
    }
    this.refreshBookmarkState()
  }

  /** P7: 导入登录态 —— 输入应用沙盒内 cookies.json 相对路径 → parse → WebCookieManager 注入 */
  @State showImportPanel: boolean = false
  // R5: 计数事件驱动（首帧时序修复：loadHistory/BOOKMARKS_CHANGED 完成后刷新）
  @State bookmarkCount: number = 0
  @State historyCount: number = 0
  private onHistoryChanged = (data: Object): void => {
    this.refreshCounts()
  }
  @State importPath: string = ''
  @State importResult: string = ''
  // P16a: 下载指示状态（DOWNLOAD_CHANGED 订阅驱动）
  @State dlActive: boolean = false
  private onDownloadChanged = (data: Object): void => {
    this.dlActive = DownloadManager.hasActive()
  }

  private importLoginState(): void {
    this.importPath = ''
    this.importResult = ''
    this.showImportPanel = true
  }

  private doImport(): void {
    const path = this.importPath.trim()
    if (path.length === 0) {
      this.importResult = '请输入 cookies.json 的沙盒相对路径'
      return
    }
    LoginStateManager.importFromCookieFile(path).then((states) => {
      const n = states.length
      const written = 0
      if (n > 0) {
        // 注入 WebView cookies
        LoginStateManager.injectCookiesToWebview().then((count) => {
          this.importResult = `已导入 ${n} 个域 / 注入 ${count} 条 cookie`
          console.info('BrowserShell import-login: domains=' + n + ' injected=' + count)
        })
      } else {
        this.importResult = '未解析到 cookie（文件不存在或格式不符）'
        console.info('BrowserShell import-login: 0 domains parsed from ' + path)
      }
      this.showImportPanel = false
      // 回显到仪表盘
      this.showDashboard = true
    })
  }

  /** P7: 导入面板 Builder（挂在 Dashboard 内） */
  @Builder
  ImportLoginPanel(): void {
    Column() {
      Text('导入登录态 (cookies.json)')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E6EDF3')
      Text('输入应用沙盒 files/ 下的相对路径，如 files/cookies.json')
        .fontSize(12)
        .fontColor('#8B949E')
        .margin({ top: 8 })
      TextInput({ text: this.importPath, placeholder: 'files/cookies.json' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(40)
        .margin({ top: 12 })
        .onChange((v: string) => { this.importPath = v })
      if (this.importResult.length > 0) {
        Text(this.importResult)
          .fontSize(12)
          .fontColor('#4CAF50')
          .margin({ top: 8 })
      }
      Row() {
        Button('取消')
          .fontSize(14)
          .width(80)
          .height(36)
          .backgroundColor('#30363D')
          .fontColor('#E6EDF3')
          .onClick(() => { this.showImportPanel = false })
        Button('导入')
          .fontSize(14)
          .width(80)
          .height(36)
          .backgroundColor('#9E6A03')
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .onClick(() => { this.doImport() })
      }
      .margin({ top: 12 })
    }
    .width('80%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor('#161B22')
  }

    
  private goHome(): void {
    console.info('BrowserShell goHome clicked')
    let dashTab = TabManager.getAllTabs().find((t: TabInfo) => t.isDashboard)
    if (!dashTab) {
      const tab = TabManager.getTab(this.activeTabId)
      if (tab) {
        tab.isDashboard = true
        dashTab = tab
      }
    }
    if (dashTab) {
      TabManager.switchTab(dashTab.tabId)
      // switchTab emit 触发 onTabStatusChange 全同步（showDashboard=true）
    }
  }

  // P11b: Chromium 标签条(内联 builder 换 TabStrip 组件);P11c: tab-search 面板
  @State showTabSearch: boolean = false
  // P11d: 书签条数据(createdAt 降序,shell 侧维护)
  @State bookmarkBarItems: BarItem[] = []
  // P11c: 网页右键菜单(Web.onContextMenuShow 拦截,手动覆盖层)
  @State ctxMenuX: number = -1
  @State ctxMenuY: number = -1
  @State ctxEntries: CtxEntry[] = []
  @State ctxLinkUrl: string = ''

  @Builder
  TabBar(): void {
    Column() {
      TabStrip({
        tabs: this.tabs,
        activeTabId: this.activeTabId,
        onTabSwitch: (tabId: string) => {
          TabManager.switchTab(tabId)
          this.activeTabId = tabId
          const tab = TabManager.getTab(tabId)
          this.showDashboard = tab ? tab.isDashboard : false
          this.currentUrl = tab && tab.currentUrl ? tab.currentUrl : ''
          this.urlInput = this.currentUrl
          this.refreshBookmarkState()
          console.info('BrowserShell tab switched: ' + tabId)
        },
        onTabClose: (tabId: string) => {
          this.closeTabById(tabId)
        },
        onTabCreate: () => {
          this.createNewTab()
        },
        onSearchToggle: () => {
          this.showTabSearch = !this.showTabSearch
        },
        tabCtxEntries: (tabId: string): CtxEntry[] => {
          return this.buildTabCtxEntries(tabId)
        }
      })
    }
    .width('100%')
  }

  /** P11c: 关闭 tab(带兜底:全关后自动建 dashboard tab) */
  private closeTabById(tabId: string): void {
    this.controllers.delete(tabId)
    this.attachedTabs.delete(tabId)
    TabManager.closeTab(tabId)
    this.tabs = TabManager.getAllTabs()
    if (this.tabs.length === 0) {
      const newTab = TabManager.createTab(true)
      this.tabs = [newTab]
      this.activeTabId = newTab.tabId
      this.showDashboard = true
    } else {
      this.activeTabId = TabManager.getActiveTabId()
      const activeTab = TabManager.getTab(this.activeTabId)
      this.showDashboard = activeTab?.isDashboard ?? true
    }
  }

  /** P11c: 网页右键菜单项(Chromium 标准项) */
  private buildPageCtxEntries(tabId: string, linkUrl: string): CtxEntry[] {
    const ctrl = this.getControllerFor(tabId)
    const canBack = ctrl ? ctrl.accessBackward() : false
    const canFwd = ctrl ? ctrl.accessForward() : false
    const pageUrl = linkUrl && linkUrl.length > 0 ? linkUrl : this.currentUrl
    const entries: CtxEntry[] = [
      {
        icon: $r('app.media.ic_back'), label: '后退', shortcut: 'Alt+左箭头', enabled: canBack, divider: false,
        onTap: () => { this.getActiveController()?.backward() }
      },
      {
        icon: $r('app.media.ic_forward'), label: '前进', shortcut: 'Alt+右箭头', enabled: canFwd, divider: false,
        onTap: () => { this.getActiveController()?.forward() }
      },
      {
        icon: $r('app.media.ic_reload'), label: '重新加载', shortcut: 'Ctrl+R', enabled: true, divider: true,
        onTap: () => { this.getActiveController()?.refresh() }
      },
      {
        icon: $r('app.media.ic_star_outline'), label: '将页面添加到书签', enabled: true, divider: true,
        onTap: () => { this.addBookmarkSilently(pageUrl) }
      },
      {
        icon: $r('app.media.ic_content_copy'), label: '复制网址', enabled: pageUrl.length > 0, divider: false,
        onTap: () => { this.copyUrl(pageUrl) }
      },
      {
        icon: $r('app.media.ic_code'), label: '查看网页源码', enabled: pageUrl.startsWith('http'), divider: false,
        onTap: () => { this.openViewSource(pageUrl) }
      }
    ]
    return entries
  }

  /** P11c: tab 右键菜单项 */
  private buildTabCtxEntries(tabId: string): CtxEntry[] {
    const idx = this.tabs.findIndex((t: TabInfo) => t.tabId === tabId)
    const hasOther = this.tabs.length > 1
    const hasRight = idx >= 0 && idx < this.tabs.length - 1
    const tab = TabManager.getTab(tabId)
    const entries: CtxEntry[] = [
      {
        icon: $r('app.media.ic_add'), label: '向右新建标签页', enabled: true, divider: false,
        onTap: () => { this.createNewTab() }
      },
      { label: '重新打开已关闭的标签页', enabled: false, divider: true },
      {
        icon: $r('app.media.ic_content_copy'), label: '复制标签页网址', enabled: !!(tab && tab.currentUrl), divider: false,
        onTap: () => { if (tab && tab.currentUrl) { this.copyUrl(tab.currentUrl) } }
      },
      {
        icon: $r('app.media.ic_close'), label: '关闭', enabled: true, divider: true,
        onTap: () => { this.closeTabById(tabId) }
      },
      {
        icon: $r('app.media.ic_close'), label: '关闭其他标签页', enabled: hasOther, divider: false,
        onTap: () => { this.closeOtherTabs(tabId) }
      },
      {
        icon: $r('app.media.ic_close'), label: '关闭右侧标签页', enabled: hasRight, divider: false,
        onTap: () => { this.closeRightTabs(tabId) }
      }
    ]
    return entries
  }

  /** P11c: 仪表盘/非网页区右键菜单项 */
  private buildDashboardCtxEntries(): CtxEntry[] {
    return [
      {
        icon: $r('app.media.ic_reload'), label: '刷新', enabled: true, divider: false,
        onTap: () => { this.getActiveController()?.refresh() }
      },
      {
        icon: $r('app.media.ic_back'), label: '后退', enabled: this.getActiveController() ? this.getActiveController()!.accessBackward() : false, divider: false,
        onTap: () => { this.getActiveController()?.backward() }
      },
      {
        icon: $r('app.media.ic_star_outline'), label: '书签管理', enabled: true, divider: true,
        onTap: () => { router.pushUrl({ url: 'pages/BookmarksPage' }) }
      }
    ]
  }

  private closeOtherTabs(keepId: string): void {
    const ids = this.tabs.map((t: TabInfo) => t.tabId).filter((id: string) => id !== keepId)
    for (const id of ids) {
      this.controllers.delete(id)
      this.attachedTabs.delete(id)
      TabManager.closeTab(id)
    }
    TabManager.switchTab(keepId)
    this.tabs = TabManager.getAllTabs()
    this.activeTabId = keepId
    console.info('BrowserShell closeOtherTabs: kept ' + keepId + ' closed ' + ids.length)
  }

  private closeRightTabs(tabId: string): void {
    const idx = this.tabs.findIndex((t: TabInfo) => t.tabId === tabId)
    if (idx < 0) {
      return
    }
    const ids = this.tabs.slice(idx + 1).map((t: TabInfo) => t.tabId)
    for (const id of ids) {
      this.controllers.delete(id)
      this.attachedTabs.delete(id)
      TabManager.closeTab(id)
    }
    this.tabs = TabManager.getAllTabs()
    console.info('BrowserShell closeRightTabs: closed ' + ids.length)
  }

  private addBookmarkSilently(url: string): void {
    if (url.length === 0 || BookmarkManager.isBookmarked(url)) {
      return
    }
    const tab = TabManager.getTab(this.activeTabId)
    const title = tab && tab.title ? tab.title : url
    BookmarkManager.addBookmark(url, title)
    this.refreshBookmarkState()
    console.info('BrowserShell ctx addBookmark: ' + url)
  }

  private copyUrl(url: string): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url)
    pasteboard.getSystemPasteboard().setData(pasteData)
    console.info('BrowserShell copyUrl: ' + url)
  }

  private openViewSource(url: string): void {
    const navParams: Record<string, Object> = { 'url': url }
    router.pushUrl({ url: 'pages/ViewSourcePage', params: navParams })
  }

  @Builder
  DashboardContent(): void {
    // P8 C1 空态：产品名 + 副标题 + 入口（查看代理/导入登录态/书签历史），对齐官网 neo 新标签页
    Column() {
      Column() {
        Text('BrowserOS neo')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ top: 24 })

        Text('给 AI 代理用的浏览器 —— 实时驾驶舱')
          .fontSize(13)
          .fontColor('#E8EAF6')
          .margin({ top: 8, bottom: 24 })
      }
      .width('86%')
      .borderRadius(20)
      .alignItems(HorizontalAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [['#2E6FE8', 0.0], ['#8B5CF6', 1.0]]
      })
      .margin({ top: 40 })

      Row() {
        Button('新建标签页')
          .fontSize(14)
          .backgroundColor('#238636')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.showDashboard = false
            const tab = TabManager.getTab(this.activeTabId)
            if (tab) {
              tab.isDashboard = false
            }
          })

        Button('查看代理')
          .fontSize(14)
          .backgroundColor('#1F6FEB')
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .onClick(() => {
            console.info('BrowserShell open NeoDashboard panel (in-shell overlay)')
            this.showNeo = true
          })

        Button('导入登录态')
          .fontSize(14)
          .backgroundColor('#9E6A03')
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .onClick(() => {
            this.importLoginState()
          })
      }
      .margin({ top: 24 })

      Text('书签 ' + this.bookmarkCount + ' 条 · 历史 ' + this.historyCount + ' 条')
        .fontSize(12)
        .fontColor('#8B949E')
        .margin({ top: 16 })

      if (this.showImportPanel) {
        this.ImportLoginPanel()
      }
      if (this.importResult.length > 0 && !this.showImportPanel) {
        Text(this.importResult)
          .fontSize(12)
          .fontColor('#4CAF50')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#0D1117')
    .bindContextMenu(this.DashboardCtxMenu(), ResponseType.LongPress)
  }

  /** P11c: 仪表盘右键菜单 Builder(系统弹窗,x=-1 仅卡体) */
  @Builder
  DashboardCtxMenu(): void {
    ContextMenu({
      x: -1,
      y: -1,
      entries: this.buildDashboardCtxEntries(),
      onClose: () => {
      }
    })
  }

  /** P5: 历史记录面板（覆盖层） */
  
  @Builder
  WebViewContent(): void {
    Stack() {
      ForEach(this.tabs, (tab: TabInfo) => {
        Web({ src: 'about:blank', controller: this.getOrCreateController(tab.tabId) })
          .width('100%')
          .height('100%')
          .visibility(tab.tabId === this.activeTabId && !this.showDashboard ? Visibility.Visible : Visibility.Hidden)
          .zIndex(tab.tabId === this.activeTabId ? 10 : 1)
          .onInterceptKeyEvent((event: KeyEvent): boolean => {
            // P11f: 页面 keydown 前拦截(仅激活 tab + 非覆盖态),Ctrl 组合消费
            if (tab.tabId !== this.activeTabId || this.showDashboard || this.showNeo) {
              return false
            }
            return this.onWebInterceptKeyEvent(event)
          })
          .onPermissionRequest((event: OnPermissionRequestEvent) => {
            // P19c: 站点资源权限请求 —— 弹层用户裁决（仅渲染弹层，request 挂起待决）
            if (event && event.request) {
              const req = event.request
              try {
                const origin = req.getOrigin()
                const resources = req.getAccessibleResource()
                this.showPermDialog(origin, resources, req)
              } catch (e) {
                console.warn('P19c perm request read fail: ' + e)
                req.deny()
              }
            }
          })
          .onControllerAttached(() => {
            // 闭包捕获事件源 tabId（多 Web 下 activeTabId 不可靠）
            const tabId = tab.tabId
            console.info('BrowserShell onControllerAttached tabId=' + tabId)
            this.attachedTabs.add(tabId)
            this.registerController(tabId)
            if (this.pendingUrl && this.pendingUrlTab === tabId) {
              const url = this.pendingUrl
              this.pendingUrl = ''
              this.pendingUrlTab = ''
              try {
                this.getControllerFor(tabId)?.loadUrl(url)
                console.info('BrowserShell pendingUrl loaded after attach: ' + url)
              } catch (e) {
                console.error('BrowserShell pendingUrl load error: ' + e)
              }
            }
            // P16b: 会话恢复 URL 补载
            if (this.restoreUrlMap.has(tabId)) {
              const rUrl = this.restoreUrlMap.get(tabId)!
              this.restoreUrlMap.delete(tabId)
              try {
                this.getControllerFor(tabId)?.loadUrl(rUrl)
                console.info('BrowserShell restoreUrl loaded after attach: ' + rUrl + ' tab=' + tabId)
              } catch (e) {
                console.error('BrowserShell restoreUrl load error: ' + e)
              }
            }
          })
          // P16a: 下载接线 —— SDK14 OnDownloadStartEvent{url,userAgent,contentDisposition,mimetype,contentLength}
          // 无 suggestedFileName 字段，文件名由 DownloadManager.extractFileName 三级推导
          .onDownloadStart((e) => {
            const fn: string = DownloadManager.fileNameFrom(e.contentDisposition, e.url)
            console.info('BrowserShell onDownloadStart url=' + e.url + ' mime=' + e.mimetype + ' len=' + e.contentLength + ' file=' + fn)
            DownloadManager.start(e.url, fn, e.mimetype)
          })
          .onPageBegin((event) => {
            this.lastNavUrl = event.url
            // P17: dashboard 标签被导航到真实页面时自动切 web 模式（P16 会话恢复后 dashboard-tab
            // 双重身份会导致地址栏=iana 而视觉仍是 dashboard 覆盖，横幅/查找条也被 !showDashboard 挡住）
            if (tab.isDashboard && event.url && !event.url.startsWith('about:')) {
              tab.isDashboard = false
              TabManager.updateTabUrl(tab.tabId, event.url)
              if (tab.tabId === this.activeTabId) {
                this.showDashboard = false
              }
              console.info('BrowserShell dashboard tab -> web mode on nav: ' + event.url)
            }
            console.info('BrowserShell onPageBegin tabId=' + tab.tabId + ' url=' + event.url)
            if (tab.tabId === this.activeTabId) {
              this.isLoading = true
              this.loadProgress = 0
              this.navError = ''
            }
          })
          .onPageEnd((event) => {
            const tabId = tab.tabId
            console.info('BrowserShell onPageEnd tabId=' + tabId + ' url=' + event.url)
            if (tabId === this.activeTabId) {
              this.isLoading = false
              this.loadProgress = 100
            }
            const url = event.url
            const controller = this.getControllerFor(tabId)
            let title = ''
            if (controller) {
              try {
                title = controller.getTitle()
              } catch (e) {
                console.error('BrowserShell getTitle error: ' + e)
              }
            }
            // 历史记录 + Tab 元数据更新
            HistoryManager.recordNavigation(tabId, url, title)
            TabManager.updateTabUrl(tabId, url)
            if (title) {
              TabManager.updateTabTitle(tabId, title)
            }
            if (tabId === this.activeTabId) {
              this.currentUrl = url
              this.urlInput = url
              this.refreshBookmarkState()
            }
            // 敏感导航检测（agentId 暂用 tabId 充当：手动导航场景）
            const sensitive = SensitiveOperationDetector.detectNavigation(tabId, url)
            if (sensitive) {
              console.info('BrowserShell sensitive navigation detected: ' + sensitive + ' url=' + url)
              // P7: 触发 ConfirmDialog 闭环
              SensitiveOperationDetector.requestConfirmation(tabId, sensitive, url, '').then((ok) => {
                console.info('BrowserShell sensitive confirm resolved: ' + ok + ' url=' + url)
              })
            }
            // 注入 BCP 桥脚本
            if (controller) {
              try {
                JSBridgeInjector.injectBridge(controller)
                JSBridgeInjector.markInjected(tabId)
                console.info('BrowserShell JSBridge injected for tabId=' + tabId)
              } catch (e) {
                console.error('BrowserShell JSBridge inject error: ' + e)
              }
            }
            const completeData: PageLoadCompleteData = { tabId: tabId, url: url }
            EventBus.emit(EventBusEvents.PAGE_LOAD_COMPLETE, completeData)
          })
          .onProgressChange((event) => {
            if (tab.tabId === this.activeTabId) {
              this.loadProgress = event.newProgress
            }
          })
          .onTitleReceive((event) => {
            if (event.title) {
              TabManager.updateTabTitle(tab.tabId, event.title)
            }
          })
          .onErrorReceive((event) => {
            console.error('BrowserShell onErrorReceive tabId=' + tab.tabId + ' url=' +
              (event.request ? event.request.getRequestUrl() : '') +
              ' error=' + (event.error ? event.error.getErrorInfo() : ''))
            {
              this.isLoading = false
              // P17a: 主文档失败 -> 错误横幅（子资源失败不打扰）
              const navTarget = this.lastNavUrl || this.pendingUrl || TabManager.getTab(tab.tabId)?.currentUrl || this.currentUrl
              const reqUrl = event.request ? event.request.getRequestUrl() : ''
              const norm = (u: string): string => u.length > 1 && u.endsWith('/') ? u.substring(0, u.length - 1) : u
              console.info('BrowserShell navErrDiag tab=' + tab.tabId + ' active=' + this.activeTabId
                + ' reqUrl=' + reqUrl + ' navTarget=' + navTarget + ' lastNavUrl=' + this.lastNavUrl
                + ' eq=' + (norm(reqUrl) === norm(navTarget)))
              if (reqUrl.length > 0 && navTarget.length > 0 && norm(reqUrl) === norm(navTarget)) {
                this.navError = event.error ? event.error.getErrorInfo() : '无法打开页面'
                this.navErrorUrl = reqUrl
                console.warn('BrowserShell navError banner: ' + reqUrl + ' ' + this.navError)
              }
            }
            const errData: PageLoadErrorData = {
              tabId: tab.tabId,
              error: event.error ? event.error.getErrorInfo() : 'unknown'
            }
            EventBus.emit(EventBusEvents.PAGE_LOAD_ERROR, errData)
          })
          .onContextMenuShow((event) => {
            // P11c: 拦截系统右键菜单,自绘 Chromium 风菜单(return true)
            if (tab.tabId !== this.activeTabId) {
              return false
            }
            const linkUrl = event.param.getLinkUrl()
            this.ctxLinkUrl = linkUrl ? linkUrl : ''
            this.ctxEntries = this.buildPageCtxEntries(tab.tabId, linkUrl)
            this.ctxMenuX = event.param.x()
            this.ctxMenuY = event.param.y() + 150
            console.info('BrowserShell ctx menu at ' + this.ctxMenuX + ',' + this.ctxMenuY + ' link=' + linkUrl)
            return true
          })
      }, (tab: TabInfo) => tab.tabId)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.pal().surface)
  }

  /** P17c: 页内查找条 —— 输入即查(window.find) / Enter 下一个 / 上一个 / 关闭 */
  @Builder
  FindBar(): void {
    if (this.showFindBar && !this.showDashboard) {
      Row() {
        Image($r('app.media.ic_find'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
        TextInput({ text: this.findQuery, placeholder: '查找页面内容' }).id('p17c_findinput')
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().text2)
          .layoutWeight(1)
          .height(32)
          .fontSize(13)
          .backgroundColor(Color.Transparent)
          .padding({ left: 4, right: 4 })
          .onChange((v: string) => {
            this.findQuery = v
            this.doFind('find')
          })
          .onSubmit(() => {
            this.doFind('next')
          })
        if (this.findStatus.length > 0) {
          Text(this.findStatus)
            .fontSize(12)
            .fontColor(this.pal().text2)
            .margin({ left: 6 })
        }
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_arrow_up'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
        }
        .width(28)
        .height(28)
        .backgroundColor(Color.Transparent)
        .margin({ left: 4 })
        .accessibilityText('查找上一个')
        .onClick(() => { this.doFind('prev') })
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_arrow_down'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
        }
        .width(28)
        .height(28)
        .backgroundColor(Color.Transparent)
        .accessibilityText('查找下一个')
        .onClick(() => { this.doFind('next') })
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_close'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
        }
        .width(28)
        .height(28)
        .backgroundColor(Color.Transparent)
        .margin({ left: 4 })
        .onClick(() => { this.closeFindBar() })
      }
      .width('80%')
      .constraintSize({ minWidth: 280 })
      .height(44)
      .padding({ left: 10, right: 10 })
      .borderRadius(8)
      .backgroundColor(this.pal().surface)
      .border({ width: 1, color: this.pal().border })
      .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
      .margin({ top: 56 })
      .zIndex(60)
    }
  }

  /** P17c: 执行查找 —— mode: 'find'(重新查) | 'next' | 'prev' */
  private doFind(mode: string): void {
    const q = this.findQuery.trim()
    if (q.length === 0) {
      this.findStatus = ''
      return
    }
    const forward = mode !== 'prev'
    console.info('BrowserShell doFind: mode=' + mode + ' q=' + q)
    BCPEngine.findText(q, forward).then((v: string) => {
      if (v === 'found') {
        this.findStatus = '有匹配'
      } else if (v === 'none') {
        this.findStatus = '无匹配'
      } else {
        this.findStatus = '此页面不支持查找'
      }
    })
  }

  /** P17c: 打开页内查找条 */
  private openFindBar(): void {
    if (this.showDashboard) {
      console.info('BrowserShell find skipped: dashboard tab')
      return
    }
    this.showFindBar = true
    this.findStatus = ''
    console.info('BrowserShell find bar opened')
  }

  /** P17c: 关闭查找条（不动页面高亮） */
  private closeFindBar(): void {
    this.showFindBar = false
    this.findStatus = ''
    console.info('BrowserShell find bar closed')
  }

  /** P17a: 导航错误横幅 —— 错误信息 + 重试(refresh) + 关闭 */
  @Builder
  ErrorBanner(): void {
    if (this.navError.length > 0) {
      Row() {
        Text(this.navErrorUrl + '\n加载失败：' + this.navError)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('重试')
          .fontSize(12)
          .height(28)
          .backgroundColor('#FFFFFF')
          .fontColor('#C5221F')
          .borderRadius(14)
          .margin({ left: 8 })
          .onClick(() => {
            console.info('BrowserShell navError retry: ' + this.navErrorUrl)
            this.navError = ''
            this.isLoading = true
            const controller = this.getActiveController()
            if (controller) {
              controller.refresh()
            } else {
              this.navigate(this.navErrorUrl)
            }
          })
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_close'))
            .width(16).height(16)
            .fillColor('#FFFFFF')
            .draggable(false)
        }
        .width(28)
        .height(28)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭错误提示')
        .margin({ left: 4 })
        .onClick(() => {
          this.navError = ''
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#C5221F')
      .zIndex(50)
    }
  }

  /** P11f: 停止加载 —— 切图标 + 手动复位 isLoading(onPageEnd 不会触发) */
  private stopActiveLoad(): void {
    console.info('BrowserShell STOP -> controller.stop() on tabId=' + this.activeTabId)
    try {
      this.getActiveController()?.stop()
    } catch (e) {
      console.error('BrowserShell stop error: ' + e)
    }
    this.isLoading = false
    this.loadProgress = 0
  }

  /** P11f: 键盘快捷键拦截(WebView 页面 keydown 前,return true=消费)
   *  映射: Ctrl+L 聚焦地址栏 / Ctrl+R 刷新 / Ctrl+T 新建标签 / Ctrl+W 关闭标签
   *  注: Web.onInterceptKeyEvent 的回调参数是 ArkUI 通用 KeyEvent(common.d.ts:10147),
   *  字段 keyCode:number / keyText / type:KeyType(Down/Up),无 modifiers 对象;
   *  keyCode 为原生 Android 风格键码,与 @kit.InputKit KeyCode 枚举同值
   *  (KEYCODE_L=2028 / KEYCODE_R=2034 / KEYCODE_T=2036 / KEYCODE_W=2039,
   *   KEYCODE_CTRL_LEFT=2072 / KEYCODE_CTRL_RIGHT=2073,SDK14 keyCode.d.ts 实测)。
   *  检测 Ctrl: 事件流里 Ctrl 键自身会先触发一个 keyCode=2072/2073 的 Down 事件,
   *  缓存到 @State ctrlHeld,组合键到达时读取;Ctrl 的 Up 事件清除。 */
  private onWebInterceptKeyEvent(event: KeyEvent): boolean {
    // Ctrl 自身按下/抬起(原生键码 2072/2073)
    if (event.keyCode === KeyCode.KEYCODE_CTRL_LEFT || event.keyCode === KeyCode.KEYCODE_CTRL_RIGHT) {
      this.ctrlHeld = event.type === 0 // KeyType.Down = 0 (SDK14 enums.d.ts:2372)
      return false // Ctrl 本身不消费,交给页面
    }
    if (!this.ctrlHeld || event.type !== 0) { // 0 = KeyType.Down, 1 = KeyType.Up
      return false
    }
    switch (event.keyCode) {
      case KeyCode.KEYCODE_L:
        console.info('BrowserShell KB Ctrl+L -> focus omnibox')
        this.focusOmnibox()
        return true
      case KeyCode.KEYCODE_R:
        console.info('BrowserShell KB Ctrl+R -> refresh')
        this.isLoading = true
        this.getActiveController()?.refresh()
        return true
      case KeyCode.KEYCODE_T:
        console.info('BrowserShell KB Ctrl+T -> new tab')
        this.createNewTab()
        return true
      case KeyCode.KEYCODE_W:
        console.info('BrowserShell KB Ctrl+W -> close tab')
        this.closeTabById(this.activeTabId)
        return true
      default:
        return false
    }
  }

  /** P11f: omnibox 聚焦(Ctrl+L 后地址栏选中态,用户直接输入替换) */
  private focusOmnibox(): void {
    this.getUIContext().getFocusController().requestFocus('p11f_omnibox')
    console.info('BrowserShell focusOmnibox requested')
  }

  private getOrCreateController(tabId: string): webview.WebviewController {
    let controller = this.controllers.get(tabId)
    if (!controller) {
      controller = new webview.WebviewController()
      this.controllers.set(tabId, controller)
      console.info('BrowserShell created WebviewController for tabId=' + tabId)
    }
    return controller
  }

  private registerController(tabId: string): void {
    const controller = this.controllers.get(tabId)
    if (controller) {
      const adapter = new WebViewAdapter(controller)
      TabManager.registerWebView(tabId, adapter, `partition_${tabId}`)
      BCPEngine.bindWebView(adapter, tabId)
      console.info('BrowserShell registered webview adapter for tabId=' + tabId)
    }
  }

  private getActiveController(): IWebviewController | null {
    const instance = TabManager.getWebView(this.activeTabId)
    return instance ? instance.controller : null
  }

  private getControllerFor(tabId: string): IWebviewController | null {
    const instance = TabManager.getWebView(tabId)
    return instance ? instance.controller : null
  }

  private onAddressInput(input: string): void {
    // P9-D: 内建 scheme —— browseros://settings|history|bookmarks|downloads|newtab
    const lower = input.trim().toLowerCase()
    if (lower.startsWith('browseros://')) {
      this.openBuiltinPage(lower)
      return
    }
    if (this.isUrl(input)) {
      this.navigate(this.normalizeUrl(input))
    } else {
      // P18: 默认搜索引擎可配置（注册表 + ConfigManager 持久化），Constants 常量保留兜底
      const eng = getEngineById(ConfigManager.getSearchEngineId())
      this.navigate(eng.queryUrl + encodeURIComponent(input))
    }
  }

  /** P9-D: browseros:// 内建页路由 */
  private openBuiltinPage(schemeUrl: string): void {
    console.info('BrowserShell builtin scheme: ' + schemeUrl)
    const page = schemeUrl.substring('browseros://'.length).replace(/\/$/, '')
    switch (page) {
      case 'settings':
        router.pushUrl({ url: 'pages/SettingsPage' })
        break
      case 'history':
        router.pushUrl({ url: 'pages/HistoryPage' })
        break
      case 'bookmarks':
        router.pushUrl({ url: 'pages/BookmarksPage' })
        break
      case 'downloads':
        router.pushUrl({ url: 'pages/DownloadsPage' })
        break
      case 'newtab':
        this.createNewTab()
        break
      default:
        console.info('BrowserShell unknown builtin page: ' + page)
        break
    }
  }

  private normalizeUrl(input: string): string {
    if (input.startsWith('https://') || input.startsWith('http://')) {
      return input
    }
    return 'https://' + input
  }

  private navigate(url: string): void {
    console.info('BrowserShell navigate to: ' + url)
    this.navError = ''
    this.currentUrl = url
    this.urlInput = url
    this.showDashboard = false
    const tab = TabManager.getTab(this.activeTabId)
    if (tab) {
      tab.isDashboard = false
      tab.currentUrl = url
    }
    TabManager.updateTabStatus(this.activeTabId, TabStatus.LOADING)
    this.isLoading = true
    const controller = this.getActiveController()
    if (controller) {
      try {
        controller.loadUrl(url)
        console.info('BrowserShell loadUrl dispatched: ' + url)
      } catch (e) {
        console.error('BrowserShell loadUrl error: ' + e)
        this.isLoading = false
      }
    } else {
      // controller 尚未 attach（tab 刚创建 ForEach 未刷新）：记目标 URL，onControllerAttached 后加载
      this.pendingUrl = url
      this.pendingUrlTab = this.activeTabId
      console.info('BrowserShell controller not ready yet, url pending: ' + url + ' tab=' + this.activeTabId)
    }
    this.refreshBookmarkState()
  }

  private isUrl(input: string): boolean {
    // P3 修复：host 支持端口号（如 http://host:11435/path）
    return /^(https?:\/\/)?([\w-]+\.)+[\w-]+(:\d{1,5})?(\/[\w-./?%&=]*)?$/.test(input)
  }

  // ---------- P9-A: chrome 补全 ----------

  /** omnibox 建议列表：书签匹配 + 历史匹配（各取前几条，去重） */
  private updateSuggestions(input: string): void {
    const kw = input.trim().toLowerCase()
    const items: SuggestItem[] = []
    const seen = new Set<string>()
    if (kw.length > 0) {
      // P11d: 首行「搜索 kw」——走搜索引擎 fallback(onPick kind=search)
      // P18: 首行带引擎名（如「百度 搜索 xx」），ChromeWidgets 直接渲染 title
      items.push({ kind: 'search', title: getEngineById(ConfigManager.getSearchEngineId()).name + ' 搜索 ' + kw, url: kw })
      const his = HistoryManager.getAllHistory(100).filter((e: HistoryEntry) =>
        e.url.toLowerCase().includes(kw) || (e.title || '').toLowerCase().includes(kw))
      for (const e of his.slice(0, 5)) {
        if (!seen.has(e.url)) {
          seen.add(e.url)
          items.push({ kind: 'history', title: e.title || '', url: e.url })
        }
      }
      const bms = BookmarkManager.searchBookmarks(kw)
      for (const b of bms.slice(0, 3)) {
        if (!seen.has(b.url)) {
          seen.add(b.url)
          items.push({ kind: 'bookmark', title: b.title, url: b.url })
        }
      }
    }
    this.suggestItems = items.slice(0, 6)
    if (this.showSuggestions && this.suggestItems.length === 0) {
      this.showSuggestions = false
    }
  }

  /** 打开书签气泡（已收藏=编辑态，未收藏=新增态） */
  private openBookmarkBubble(): void {
    if (this.currentUrl.length === 0) {
      console.info('BrowserShell bookmark bubble skipped: no url')
      return
    }
    this.bookmarkBubbleUrl = this.currentUrl
    this.bookmarkBubbleExisting = BookmarkManager.isBookmarked(this.currentUrl)
    if (this.bookmarkBubbleExisting) {
      const id = BookmarkManager.getBookmarkIdByUrl(this.currentUrl)
      const bm = id ? BookmarkManager.getBookmark(id) : null
      this.bookmarkBubbleTitle = bm && bm.title ? bm.title : this.currentUrl
    } else {
      const tab = TabManager.getTab(this.activeTabId)
      this.bookmarkBubbleTitle = tab && tab.title ? tab.title : this.currentUrl
    }
    this.showBookmarkBubble = true
    console.info('BrowserShell bookmark bubble opened: ' + this.currentUrl + ' existing=' + this.bookmarkBubbleExisting)
  }

  /** 气泡"完成"：新增或改名 */
  private finishBookmarkEdit(): void {
    const url = this.bookmarkBubbleUrl
    const title = this.bookmarkBubbleTitle.trim().length > 0 ? this.bookmarkBubbleTitle.trim() : url
    if (BookmarkManager.isBookmarked(url)) {
      const id = BookmarkManager.getBookmarkIdByUrl(url)
      if (id) {
        BookmarkManager.updateBookmark(id, undefined, title)
        console.info('BrowserShell bookmark renamed: ' + title)
      }
    } else {
      BookmarkManager.addBookmark(url, title)
      console.info('BrowserShell bookmark added: ' + url + ' title=' + title)
    }
    this.showBookmarkBubble = false
    this.refreshBookmarkState()
  }

  /** 气泡"删除" */
  private removeCurrentBookmark(): void {
    const id = BookmarkManager.getBookmarkIdByUrl(this.bookmarkBubbleUrl)
    if (id) {
      BookmarkManager.removeBookmark(id)
      console.info('BrowserShell bookmark removed via bubble: ' + this.bookmarkBubbleUrl)
    }
    this.showBookmarkBubble = false
    this.refreshBookmarkState()
  }

  /** ⋮ 菜单动作分发 */
  private onMenuAction(action: string): void {
    console.info('BrowserShell menu action: ' + action)
    this.showMenu = false
    switch (action) {
      case 'new_tab':
        this.createNewTab()
        break
      case 'new_window':
        // P9-C5：多窗口退化为新建标签页（如实记录）
        this.createNewTab()
        break
      case 'history':
        router.pushUrl({ url: 'pages/HistoryPage' })
        break
      case 'bookmarks':
        router.pushUrl({ url: 'pages/BookmarksPage' })
        break
      case 'downloads':
        router.pushUrl({ url: 'pages/DownloadsPage' })
        break
      case 'settings':
        router.pushUrl({ url: 'pages/SettingsPage' })
        break
      case 'find':
        this.openFindBar()
        break
      case 'help':
        // P9r: 帮助 = 新标签页导航官网（真实 Web 标签）
        this.createNewTab()
        this.navigate('https://www.browseros.com')
        break
      case 'exit':
        (this.getUIContext().getHostContext() as common.UIAbilityContext).terminateSelf()
        break
      default:
        break
    }
  }

  /** 新建空白标签页（切到 dashboard 态） */
  private createNewTab(): void {
    const newTab = TabManager.createTab(true)
    this.tabs = TabManager.getAllTabs()
    this.activeTabId = newTab.tabId
    this.showDashboard = true
    this.urlInput = ''
    this.currentUrl = ''
    console.info('BrowserShell new tab created: ' + newTab.tabId)
  }
}