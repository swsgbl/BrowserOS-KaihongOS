import { TabManager } from '../service/TabManager'
import { IWebviewController } from '../common/IWebviewController'
import { WebViewAdapter } from '../protocol/WebViewAdapter'
import { HistoryManager, HistoryEntry } from '../service/HistoryManager'
import { BookmarkManager } from '../service/BookmarkManager'
import { SensitiveOperationDetector } from '../service/SensitiveOperationDetector'
import { BCPEngine } from '../protocol/BCPEngine'
import { JSBridgeInjector } from '../protocol/JSBridgeInjector'
import { Constants } from '../common/Constants'
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
import { ContextMenu, CtxEntry, ctxDivider } from '../components/ContextMenu'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { Palette } from '../common/Palette'

interface PageLoadErrorData {
  tabId: string
  error: string
}

interface PageLoadCompleteData {
  tabId: string
  url: string
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
  @State showDashboard: boolean = true
  @State loadProgress: number = 0
  @State isBookmarked: boolean = false
  @State showHistory: boolean = false
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
  @State historyItems: HistoryEntry[] = []
  // 每个 Tab 独立的 WebviewController（key=tabId）
  private controllers: Map<string, webview.WebviewController> = new Map()
  private pendingUrl: string = ''
  private pendingUrlTab: string = ''
  // P5: 覆盖态（NeoDashboard 前台）@State 赋值不驱动渲染；返回时需强制 ForEach 重建
  private tabsDirty: boolean = false
  /** P5: 覆盖态标记 —— NeoDashboardPage/Onboarding 覆盖时 BrowserShell 不可见 */
  private covering: boolean = false
  private attachedTabs: Set<string> = new Set()

  aboutToAppear(): void {
    console.info('BrowserShell aboutToAppear start')
    try {
      this.tabs = TabManager.getAllTabs()
      console.info('BrowserShell tabs loaded: ' + this.tabs.length)
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

  private refreshBookmarkState(): void {
    this.isBookmarked = this.currentUrl.length > 0 && BookmarkManager.isBookmarked(this.currentUrl)
  }

  build(): void {
    Stack() {
      Column() {
        this.AddressBar()
        this.TabBar()
      // P6 治本：Web 层常驻 —— 所有 tab 的 Web 组件始终挂载（非激活 Hidden 保活），
      // dashboard/NeoDashboard 作为覆盖层置顶。修复「dashboard 激活时全部 Web 销毁、
      // 覆盖态 ForEach 不新增」的时序缺口：agent tab 创建即有 WebView，BCP 立即可用。
      Stack() {
        this.WebViewContent()
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
      if (this.showHistory) {
        this.HistoryPanel()
      }
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
          onPick: (url: string) => {
            console.info('BrowserShell suggestion picked: ' + url)
            this.showSuggestions = false
            this.navigate(this.normalizeUrl(url))
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
        .backgroundColor(this.pal().surface)
        .shadow({ radius: 12, color: '#33000000', offsetX: -4, offsetY: 0 })
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

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_reload'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        console.info('BrowserShell refresh button clicked, tabId=' + this.activeTabId)
        const controller = this.getActiveController()
        if (controller) {
          console.info('BrowserShell REFRESH -> controller.refresh() on tabId=' + this.activeTabId)
          this.isLoading = true
          controller.refresh()
        } else {
          console.info('BrowserShell REFRESH skipped: controller not attached, tabId=' + this.activeTabId)
        }
      })

      // P9-A: omnibox —— 安全锁图标（https 绿锁 / 普通灰）+ 输入框胶囊
      Row() {
        Image(this.currentUrl.startsWith('https://') ? $r('app.media.ic_lock') : $r('app.media.ic_info'))
          .width(16).height(16)
          .fillColor(this.currentUrl.startsWith('https://') ? '#137333' : '#5F6368')
          .draggable(false)
        TextInput({ text: this.urlInput, placeholder: '输入URL或搜索关键词' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
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
      .onClick(() => {
        this.openHistory()
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
  @State importPath: string = ''
  @State importResult: string = ''

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

  /** P5: 历史面板（HistoryManager 接线） */
  private openHistory(): void {
    this.historyItems = HistoryManager.getAllHistory(50)
    this.showHistory = true
    console.info('BrowserShell history opened: ' + this.historyItems.length + ' entries')
  }

  /** P5: 回首页 —— 切换到 Dashboard 标签（找不到则把当前 tab 置为 Dashboard） */
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
        icon: $r('app.media.ic_back'), label: '后退', shortcut: 'Alt+←', enabled: canBack, divider: false,
        onTap: () => { this.getActiveController()?.backward() }
      },
      {
        icon: $r('app.media.ic_forward'), label: '前进', shortcut: 'Alt+→', enabled: canFwd, divider: false,
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

      Text('书签 ' + BookmarkManager.getBookmarkCount() + ' 条 · 历史 ' + HistoryManager.getAllHistory(500).length + ' 条')
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
  HistoryPanel(): void {
    Column() {
      Row() {
        Text('历史记录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E6EDF3')
          .layoutWeight(1)

        Button('关闭')
          .fontSize(14)
          .height(36)
          .backgroundColor('#30363D')
          .fontColor('#E6EDF3')
          .onClick(() => {
            this.showHistory = false
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })

      if (this.historyItems.length === 0) {
        Text('暂无历史记录')
          .fontSize(14)
          .fontColor('#8B949E')
          .margin({ top: 32 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.historyItems, (entry: HistoryEntry, index: number) => {
              Column() {
                Text(entry.title && entry.title.length > 0 ? entry.title : entry.url)
                  .fontSize(13)
                  .fontColor('#E6EDF3')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(entry.url)
                  .fontSize(10)
                  .fontColor('#8B949E')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .borderRadius(6)
              .backgroundColor('#161B22')
              .margin({ top: 6 })
              .onClick(() => {
                console.info('BrowserShell history item clicked: ' + entry.url)
                this.showHistory = false
                this.navigate(this.normalizeUrl(entry.url))
              })
            }, (entry: HistoryEntry, index: number) => entry.url + '_' + entry.timestamp + '_' + index)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .align(Alignment.Top)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#0D1117F0')
  }

  /** P5: 多 Web 并行架构 —— 每个 tab 常驻一个 Web 组件（Hidden 保活），
   *  active tab 可见。agent tab 创建即挂载（onControllerAttached → registerWebView
   *  → BCPEngine.bindWebView），从根上解决 P4 的 "agent tab 无 WebView" 缺口 */
  @Builder
  WebViewContent(): void {
    Stack() {
      ForEach(this.tabs, (tab: TabInfo) => {
        Web({ src: 'about:blank', controller: this.getOrCreateController(tab.tabId) })
          .width('100%')
          .height('100%')
          .visibility(tab.tabId === this.activeTabId && !this.showDashboard ? Visibility.Visible : Visibility.Hidden)
          .zIndex(tab.tabId === this.activeTabId ? 10 : 1)
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
          })
          .onPageBegin((event) => {
            console.info('BrowserShell onPageBegin tabId=' + tab.tabId + ' url=' + event.url)
            if (tab.tabId === this.activeTabId) {
              this.isLoading = true
              this.loadProgress = 0
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
            if (tab.tabId === this.activeTabId) {
              this.isLoading = false
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
      this.navigate(Constants.DEFAULT_SEARCH_ENGINE + encodeURIComponent(input))
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
      const bms = BookmarkManager.searchBookmarks(kw)
      for (const b of bms.slice(0, 3)) {
        if (!seen.has(b.url)) {
          seen.add(b.url)
          items.push({ kind: 'bookmark', title: b.title, url: b.url })
        }
      }
      const his = HistoryManager.getAllHistory(100).filter((e: HistoryEntry) =>
        e.url.toLowerCase().includes(kw) || (e.title || '').toLowerCase().includes(kw))
      for (const e of his.slice(0, 5)) {
        if (!seen.has(e.url)) {
          seen.add(e.url)
          items.push({ kind: 'history', title: e.title || '', url: e.url })
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
