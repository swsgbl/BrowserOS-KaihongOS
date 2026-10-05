
import { TabManager } from '../service/TabManager'
import { IWebviewController } from '../common/IWebviewController'
import { HistoryManager } from '../service/HistoryManager'
import { BookmarkManager } from '../service/BookmarkManager'
import { BCPEngine } from '../protocol/BCPEngine'
import { JSBridgeInjector } from '../protocol/JSBridgeInjector'
import { Constants } from '../common/Constants'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { TabStatus } from '../common/Types'
import { TabInfo } from '../model/TabInfo'

interface PageLoadErrorData {
  tabId: string
  error: string
}

@Entry
@Component
struct BrowserShell {
  @State currentUrl: string = ''
  @State urlInput: string = ''
  @State tabs: TabInfo[] = []
  @State activeTabId: string = ''
  @State isLoading: boolean = false
  @State showDashboard: boolean = true
  private webviewController: IWebviewController | null = null

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

  private onTabStatusChange = (data: Object): void => {
    try {
      this.tabs = TabManager.getAllTabs()
    } catch (e) {
      console.error('BrowserShell onTabStatusChange error: ' + e)
    }
  }

  build(): void {
    Column() {
      this.AddressBar()
      this.TabBar()
      if (this.showDashboard) {
        this.DashboardContent()
      } else {
        this.WebViewContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  AddressBar(): void {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Text('←')
          .fontSize(18)
          .fontColor('#666666')
      }
      .width(36)
      .height(36)
      .onClick(() => {
        const backUrl = HistoryManager.getBackUrl(this.activeTabId)
        if (backUrl) {
          this.navigate(backUrl)
        }
      })

      Button({ type: ButtonType.Normal }) {
        Text('→')
          .fontSize(18)
          .fontColor('#666666')
      }
      .width(36)
      .height(36)
      .onClick(() => {
        const forwardUrl = HistoryManager.getForwardUrl(this.activeTabId)
        if (forwardUrl) {
          this.navigate(forwardUrl)
        }
      })

      Button({ type: ButtonType.Normal }) {
        Text('↻')
          .fontSize(18)
          .fontColor('#666666')
      }
      .width(36)
      .height(36)
      .onClick(() => {
        if (this.currentUrl) {
          this.isLoading = true
        }
      })

      TextInput({ text: this.urlInput, placeholder: '输入URL或搜索关键词' })
        .layoutWeight(1)
        .height(36)
        .type(InputType.Normal)
        .onChange((value: string) => {
          this.urlInput = value
        })
        .onSubmit(() => {
          this.onAddressInput(this.urlInput)
        })

      Button({ type: ButtonType.Normal }) {
        Text('⌂')
          .fontSize(18)
          .fontColor('#666666')
      }
      .width(36)
      .height(36)
      .onClick(() => {
        this.showDashboard = true
        TabManager.updateTabStatus(this.activeTabId, TabStatus.IDLE)
      })
    }
    .width('100%')
    .height(48)
    .padding({ left: 8, right: 8 })
    .backgroundColor('#F5F5F5')
  }

  @Builder
  TabBar(): void {
    Row() {
      ForEach(this.tabs, (tab: TabInfo) => {
        Row() {
          Text(tab.title || '新标签页')
            .fontSize(12)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .fontColor(tab.tabId === this.activeTabId ? '#007DFF' : '#333333')

          if (tab.tabId === this.activeTabId) {
            Text(' ●')
              .fontSize(10)
              .fontColor('#007DFF')
          }

          Button({ type: ButtonType.Normal }) {
            Text('×')
              .fontSize(14)
              .fontColor('#999999')
          }
          .width(20)
          .height(20)
          .onClick(() => {
            TabManager.closeTab(tab.tabId)
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
          })
        }
        .padding({ left: 8, right: 4 })
        .height(32)
        .borderRadius(4)
        .backgroundColor(tab.tabId === this.activeTabId ? '#E6F2FF' : '#FFFFFF')
        .onClick(() => {
          TabManager.switchTab(tab.tabId)
          this.activeTabId = tab.tabId
          this.currentUrl = tab.currentUrl
          this.urlInput = tab.currentUrl
          this.showDashboard = tab.isDashboard
        })
      })

      Button({ type: ButtonType.Normal }) {
        Text('+')
          .fontSize(16)
          .fontColor('#666666')
      }
      .width(32)
      .height(32)
      .onClick(() => {
        const newTab = TabManager.createTab(true)
        this.tabs = TabManager.getAllTabs()
        this.activeTabId = newTab.tabId
        this.showDashboard = true
        this.urlInput = ''
        this.currentUrl = ''
      })
    }
    .width('100%')
    .height(36)
    .padding({ left: 4, right: 4 })
    .backgroundColor('#F0F0F0')
  }

  @Builder
  DashboardContent(): void {
    Column() {
      Text('BrowserOS KaihongOS')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ top: 40 })

      Text('AI代理浏览器 - 深开鸿版本')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 8 })

      Row() {
        Button('新建标签页')
          .fontSize(14)
          .backgroundColor('#007DFF')
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
          .backgroundColor('#4CAF50')
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .onClick(() => {
          })

        Button('导入登录态')
          .fontSize(14)
          .backgroundColor('#FF9800')
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .onClick(() => {
          })
      }
      .margin({ top: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FFFFFF')
  }

  @Builder
  WebViewContent(): void {
    Column() {
      Text('网页浏览功能')
        .fontSize(18)
        .fontColor('#333333')
        .margin({ top: 40 })

      Text('Web组件在当前系统上暂不可用')
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 8 })

      Text('请使用仪表盘功能')
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 4 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FFFFFF')
  }

  private onAddressInput(input: string): void {
    if (this.isUrl(input)) {
      this.navigate(input)
    } else {
      this.navigate(Constants.DEFAULT_SEARCH_ENGINE + encodeURIComponent(input))
    }
  }

  private navigate(url: string): void {
    this.currentUrl = url
    this.urlInput = url
    this.showDashboard = false
    const tab = TabManager.getTab(this.activeTabId)
    if (tab) {
      tab.isDashboard = false
      tab.currentUrl = url
    }
    TabManager.updateTabStatus(this.activeTabId, TabStatus.LOADING)
  }

  private isUrl(input: string): boolean {
    return /^(https?:\/\/)?([\w-]+\.)+[\w-]+(\/[\w-./?%&=]*)?$/.test(input)
  }
}