/**
 * P11b: Chromium 形标签条组件
 * - active tab = 内容色(pal.surface) + 上圆角 8,与下方内容区无缝衔接
 * - inactive = 半透明(浅 rgba(0,0,0,.05) / 深 rgba(255,255,255,.05)),hover 变亮
 * - 每标签: favicon 方块(agent=ic_robot) + 标题截断 + 关闭按钮(hover/active 可见)
 * - 尾部: ic_add 新标签 + ic_tab_search 打开标签页搜索面板
 * 红线: 每标签 layoutWeight(1) 等宽(历史验收行为) 保留
 */
import { TabInfo } from '../model/TabInfo'
import { Palette } from '../common/Palette'
import { ContextMenu, CtxEntry } from './ContextMenu'

@Component
export struct TabStrip {
  @StorageProp('darkMode') darkMode: boolean = false
  @State hoverTabId: string = ''
  tabs: TabInfo[] = []
  activeTabId: string = ''
  onTabSwitch?: (tabId: string) => void
  onTabClose?: (tabId: string) => void
  onTabCreate?: () => void
  onSearchToggle?: () => void
  /** P11c: 标签右键菜单构建器(shell 注入,避免循环依赖) */
  tabCtxEntries?: (tabId: string) => CtxEntry[]
  /** P28: 竖排模式(原生 v0.42+ vertical tabs) —— false 保留旧横排兼容 */
  vertical: boolean = false

  /** P11c: 标签右键菜单 Builder */
  @Builder
  TabCtxMenu(tabId: string): void {
    ContextMenu({
      x: -1,
      y: -1,
      entries: this.tabCtxEntries ? this.tabCtxEntries(tabId) : [],
      onClose: () => {
      }
    })
  }

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  private inactiveBg(tabId: string): string {
    const hovered = this.hoverTabId === tabId
    if (this.darkMode) {
      return hovered ? '#1FFFFFFF' : '#0DFFFFFF'
    }
    return hovered ? '#14000000' : '#0D000000'
  }

  build(): void {
    if (this.vertical) {
      this.VerticalTabs()
    } else {
      this.HorizontalTabs()
    }
  }

  /** P28-A: 竖排标签条(左侧栏,List 竖向滚动,激活=左侧大圆角+surface 色) */
  @Builder
  VerticalTabs(): void {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.tabs, (tab: TabInfo) => {
            Stack() {
              Row() {
                Stack() {
                  Image(tab.agentId ? $r('app.media.ic_robot') : $r('app.media.ic_globe'))
                    .width(12).height(12)
                    .fillColor(tab.agentId ? '#8AB4F8' : (tab.tabId === this.activeTabId ? '#5F6368' : '#80868B'))
                    .draggable(false)
                }
                .width(18).height(18)
                .borderRadius(3)
                .backgroundColor(tab.tabId === this.activeTabId
                  ? (this.darkMode ? '#3C4043' : '#F1F3F4') : '#12000000')

                Text(tab.title || (tab.agentId ? '代理 ' + tab.agentId.substring(0, 12) : '新标签页'))
                  .fontSize(12)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .fontColor(tab.tabId === this.activeTabId ? this.pal().text : this.pal().text2)

                Button({ type: ButtonType.Normal }) {
                  Image($r('app.media.ic_close'))
                    .width(16).height(16)
                    .fillColor(this.pal().text2)
                    .draggable(false)
                }
                .width(28)
                .height(28)
                .opacity(1)
                .backgroundColor(Color.Transparent)
                .hitTestBehavior(HitTestMode.Default)
                .accessibilityText('关闭标签页 ' + (tab.title || '新标签页'))
                .onClick(() => {
                  if (this.onTabClose) {
                    this.onTabClose(tab.tabId)
                  }
                })
              }
              .padding({ left: 8, right: 4 })
              .height(32)
              .width('100%')
              .borderRadius({ topLeft: 8, bottomLeft: 8 })
              .backgroundColor(tab.tabId === this.activeTabId
                ? this.pal().surface
                : this.inactiveBg(tab.tabId))
              .onClick(() => {
                if (this.onTabSwitch) {
                  this.onTabSwitch(tab.tabId)
                }
              })
              .onHover((isHover: boolean) => {
                this.hoverTabId = isHover ? tab.tabId : ''
              })
            }
            .width('100%')
            .height(32)
            .bindContextMenu(this.TabCtxMenu(tab.tabId), ResponseType.LongPress)
          }, (tab: TabInfo) => tab.tabId)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)

      // P28-C: tab-search 入口移到竖排条底部(与 ic_add 并排)
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_add'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
        }
        .width(28).height(28)
        .backgroundColor(Color.Transparent)
        .accessibilityText('新建标签页')
        .onClick(() => {
          if (this.onTabCreate) {
            this.onTabCreate()
          }
        })

        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_tab_search'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
        }
        .width(28).height(28)
        .backgroundColor(Color.Transparent)
        .accessibilityText('搜索标签页')
        .onClick(() => {
          if (this.onSearchToggle) {
            this.onSearchToggle()
          }
        })
      }
      .width('100%')
      .height(36)
      .padding({ left: 6, right: 6 })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  /** P11b: 横排标签条(保留,vertical=false 走此分支) */
  @Builder
  HorizontalTabs(): void {
    Row() {
      ForEach(this.tabs, (tab: TabInfo) => {
        Stack() {
          Row() {
            // favicon 方块(18x18 圆角小瓦片,内嵌 12px SVG)
            Stack() {
              Image(tab.agentId ? $r('app.media.ic_robot') : $r('app.media.ic_globe'))
                .width(12).height(12)
                .fillColor(tab.agentId ? '#8AB4F8' : (tab.tabId === this.activeTabId ? '#5F6368' : '#80868B'))
                .draggable(false)
            }
            .width(18).height(18)
            .borderRadius(3)
            .backgroundColor(tab.tabId === this.activeTabId
              ? (this.darkMode ? '#3C4043' : '#F1F3F4') : '#12000000')

            Text(tab.title || (tab.agentId ? '代理 ' + tab.agentId.substring(0, 12) : '新标签页'))
              .fontSize(12)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .fontColor(tab.tabId === this.activeTabId ? this.pal().text : this.pal().text2)

            Button({ type: ButtonType.Normal }) {
              Image($r('app.media.ic_close'))
                .width(14).height(14)
                .fillColor(this.pal().text2)
                .draggable(false)
            }
            .width(22)
            .height(22)
            .opacity(1)
            .backgroundColor(Color.Transparent)
            .accessibilityText('关闭标签页 ' + (tab.title || '新标签页'))
            .onClick(() => {
              if (this.onTabClose) {
                this.onTabClose(tab.tabId)
              }
            })
          }
          .padding({ left: 8, right: 4 })
          .height(30)
          .width('100%')
          .borderRadius({ topLeft: 8, topRight: 8 })
          .backgroundColor(tab.tabId === this.activeTabId
            ? this.pal().surface
            : this.inactiveBg(tab.tabId))
          .onClick(() => {
            if (this.onTabSwitch) {
              this.onTabSwitch(tab.tabId)
            }
          })
          .onHover((isHover: boolean) => {
            this.hoverTabId = isHover ? tab.tabId : ''
          })
        }
        .layoutWeight(1)
        .height(30)
        .bindContextMenu(this.TabCtxMenu(tab.tabId), ResponseType.LongPress)
      }, (tab: TabInfo) => tab.tabId)

      // 新标签按钮
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_add'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
      }
      .width(30)
      .height(30)
      .margin({ left: 2 })
      .backgroundColor(Color.Transparent)
      .accessibilityText('新建标签页')
      .onClick(() => {
        if (this.onTabCreate) {
          this.onTabCreate()
        }
      })

      // tab-search 按钮(打开的标签页面板)
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_tab_search'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
      }
      .width(30)
      .height(30)
      .backgroundColor(Color.Transparent)
      .accessibilityText('搜索标签页')
      .onClick(() => {
        if (this.onSearchToggle) {
          this.onSearchToggle()
        }
      })
    }
    .width('100%')
    .height(32)
    .padding({ left: 4, right: 4 })
    .backgroundColor(this.pal().surfaceAlt)
  }
}

/** tab-search 面板:打开的标签页列表(favicon+标题+关闭),点击切换 */
@Component
export struct TabSearchPanel {
  @StorageProp('darkMode') darkMode: boolean = false
  tabs: TabInfo[] = []
  activeTabId: string = ''
  onPick: (tabId: string) => void = (tabId: string) => {}
  onCloseTab: (tabId: string) => void = (tabId: string) => {}
  onCreate: () => void = () => {}
  onClose: () => void = () => {}

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  build(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 全屏透明遮罩:点击任意处关闭
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.onClose()
        })

      Column() {
        Text('打开的标签页')
          .fontSize(11)
          .fontColor(this.pal().text2)
          .padding({ left: 12, top: 8, bottom: 4 })
          .alignSelf(ItemAlign.Start)

        Scroll() {
          Column() {
            ForEach(this.tabs, (tab: TabInfo) => {
              Row() {
                Image(tab.agentId ? $r('app.media.ic_robot') : $r('app.media.ic_globe'))
                  .width(16).height(16)
                  .fillColor(tab.agentId ? '#8AB4F8' : this.pal().text2)
                  .margin({ right: 8 })
                  .draggable(false)
                Text(tab.title || '新标签页')
                  .fontSize(13)
                  .fontColor(this.pal().text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Button({ type: ButtonType.Normal }) {
                  Image($r('app.media.ic_close'))
                    .width(16).height(16)
                    .fillColor(this.pal().text2)
                    .draggable(false)
                }
                .width(22).height(22)
                .backgroundColor(Color.Transparent)
                .accessibilityText('关闭标签页 ' + (tab.title || '新标签页'))
                .onClick(() => {
                  this.onCloseTab(tab.tabId)
                })
              }
              .width('100%')
              .height(36)
              .padding({ left: 12, right: 8 })
              .borderRadius(6)
              .backgroundColor(tab.tabId === this.activeTabId ? this.pal().selected : Color.Transparent)
              .onClick(() => {
                this.onPick(tab.tabId)
              })
            }, (tab: TabInfo) => tab.tabId)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 300 })
        .align(Alignment.Start)

        Divider().color(this.pal().border).margin({ top: 4, bottom: 4 })

        Row() {
          Image($r('app.media.ic_add'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .margin({ right: 8 })
            .draggable(false)
          Text('新建标签页')
            .fontSize(13)
            .fontColor(this.pal().text)
        }
        .width('100%')
        .height(36)
        .padding({ left: 12, right: 12 })
        .borderRadius(6)
        .onClick(() => {
          this.onCreate()
        })
      }
      .width(280)
      .padding(6)
      .borderRadius(12)
      .backgroundColor(this.pal().surface)
      .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
      .margin({ top: 40, right: 8 })
    }
    .width('100%')
    .height('100%')
  }
}
