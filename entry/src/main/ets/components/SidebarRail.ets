/**
 * P28-B: hover 自动展开/收起侧边菜单栏(原生 AppSidebar.tsx 复刻)
 * - 收起态 14vp 宽:仅竖排图标(Home/定时/连接/设置 16vp 居中)
 * - 展开态 64vp:图标+文字标签(两行式,上游 SidebarNavigation NavLink)
 * - onHover 展开/收起, animation 200ms EaseInOut (upstream transition-all duration-200)
 * - 底部帮助;背景 pal().surfaceAlt;展开时右缘 1px hairline
 */
import { Palette } from '../common/Palette'
import { I18n } from '../common/I18n'

@Component
export struct SidebarRail {
  // P48: locale 刷新锚 —— @StorageProp 变化时递增 version 驱动本 struct 重渲染
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44
  /** hover 展开态(受控于 onHover;P46-A 手动展开时锁定) */
  @State expanded: boolean = false
  /** P46-A: 手动展开锁定位 —— 点击底部切换按钮置位;置位后 hover 离开不收回 */
  @State pinned: boolean = false
  /** 当前激活项 id: home|scheduled|connect|settings|help */
  @Prop activeId: string = 'home'
  onNav?: (target: string) => void

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @Builder
  RailIcon(res: Resource, labelKey: string, id: string) {
    if (this.expanded) {
      // 展开态:图标+文字两行式(64vp 宽)
      Column() {
        Image(res)
          .width(16).height(16)
          .fillColor(this.activeId === id ? '#1A73E8' : this.pal().text2)
          .draggable(false)
        Text(I18n.t(labelKey))
          .fontSize(9)
          .maxLines(1)
          .margin({ top: 2 })
          .fontColor(this.activeId === id ? '#1A73E8' : this.pal().text2)
      }
      .width(48)
      .height(48)
      .borderRadius(8)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.activeId === id ? this.pal().selected : Color.Transparent)
      .onClick(() => {
        if (this.onNav) {
          this.onNav(id)
        }
      })
    } else {
      // 收起态:仅图标(14vp 宽竖条,16vp 图标整体居中)
      Image(res)
        .width(16).height(16)
        .fillColor(this.activeId === id ? '#1A73E8' : this.pal().text2)
        .draggable(false)
        .accessibilityText(I18n.t(labelKey))
        .onClick(() => {
          if (this.onNav) {
            this.onNav(id)
          }
        })
    }
  }

  /** P46-A: 手动收纳/展开切换按钮(上游 expanded prop 的本地控制位;上游收起 w-14/展开 w-64) */
  @Builder
  RailToggle(): void {
    Button({ type: ButtonType.Normal }) {
      Column() {
        Image($rawfile('ic_menu.svg'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
        if (this.expanded) {
          Text(this.pinned ? I18n.t('railCollapse') : I18n.t('railExpand'))
            .fontSize(9)
            .maxLines(1)
            .margin({ top: 2 })
            .fontColor(this.pal().text2)
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.expanded ? 48 : 14)
    .height(this.expanded ? 44 : 26)
    .margin({ top: 6 })
    .borderRadius(8)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.expanded ? I18n.t('railCollapseSide') : I18n.t('railExpandSide'))
    .onClick(() => {
      this.pinned = !this.pinned
      this.expanded = this.pinned
      console.info('P46 rail toggle: pinned=' + this.pinned)
    })
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('SidebarRail theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Column() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // P51-C: localeVersion anchor (re-render on locale flip — @Watch fired but no render dependency was the bug)
        if (this.localeVersion < 0) {
          Text('').fontSize(0)
        }

      // 顶部 logo 位(收起态不显示,展开态小图标)
      if (this.expanded) {
        Image($rawfile('ic_public.svg'))
          .width(18).height(18)
          .fillColor('#1A73E8')
          .draggable(false)
          .margin({ top: 6, bottom: 4 })
      }

      // 四项导航(收起=竖排居中,展开=竖排 48px 方块)
      Column({ space: this.expanded ? 2 : 12 }) {
        this.RailIcon($rawfile('ic_home.svg'), 'railHome', 'home')
        this.RailIcon($rawfile('ic_schedule.svg'), 'railScheduled', 'scheduled')
        this.RailIcon($rawfile('ic_agent.svg'), 'railConnect', 'connect')
        this.RailIcon($rawfile('ic_settings.svg'), 'railSettings', 'settings')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.expanded ? 4 : 10 })
      .alignItems(HorizontalAlign.Center)

      // 底部帮助 + P46-A 收纳/展开切换
      Column() {
        this.RailIcon($rawfile('ic_help.svg'), 'railHelp', 'help')
        this.RailToggle()
      }
      .margin({ bottom: 6 })
    }
    .width(this.expanded ? 64 : 14)
    .height('100%')
    .padding({ left: this.expanded ? 8 : 0, right: this.expanded ? 8 : 0 })
    .backgroundColor(this.pal().surfaceAlt)
    .border({ width: { right: 1 }, color: this.pal().border })
    .alignItems(HorizontalAlign.Center)
    .onHover((isHover: boolean) => {
      // P46-A: 手动展开(pinned)时 hover 不改变状态;未锁定时保留 hover 临时展开
      if (!this.pinned) {
        this.expanded = isHover
      }
    })
    .animation({ duration: 200, curve: Curve.EaseInOut })
  }
}
