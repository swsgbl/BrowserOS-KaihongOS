/**
 * P28-B: hover 自动展开/收起侧边菜单栏(原生 AppSidebar.tsx 复刻)
 * - 收起态 14vp 宽:仅竖排图标(Home/定时/连接/设置 16vp 居中)
 * - 展开态 64vp:图标+文字标签(两行式,上游 SidebarNavigation NavLink)
 * - onHover 展开/收起, animation 200ms EaseInOut (upstream transition-all duration-200)
 * - 底部帮助;背景 pal().surfaceAlt;展开时右缘 1px hairline
 */
import { Palette } from '../common/Palette'

@Component
export struct SidebarRail {
  @StorageProp('darkMode') darkMode: boolean = false
  /** hover 展开态(受控于 onHover) */
  @State expanded: boolean = false
  /** 当前激活项 id: home|scheduled|connect|settings|help */
  @Prop activeId: string = 'home'
  onNav?: (target: string) => void

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @Builder
  RailIcon(res: Resource, label: string, id: string) {
    if (this.expanded) {
      // 展开态:图标+文字两行式(64vp 宽)
      Column() {
        Image(res)
          .width(16).height(16)
          .fillColor(this.activeId === id ? '#1A73E8' : this.pal().text2)
          .draggable(false)
        Text(label)
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
    }
  }

  build(): void {
    Column() {
      // 顶部 logo 位(收起态不显示,展开态小图标)
      if (this.expanded) {
        Image($r('app.media.ic_public'))
          .width(18).height(18)
          .fillColor('#1A73E8')
          .draggable(false)
          .margin({ top: 6, bottom: 4 })
      }

      // 四项导航(收起=竖排居中,展开=竖排 48px 方块)
      Column({ space: this.expanded ? 2 : 12 }) {
        this.RailIcon($r('app.media.ic_home'), '主页', 'home')
        this.RailIcon($r('app.media.ic_schedule'), '定时', 'scheduled')
        this.RailIcon($r('app.media.ic_agent'), '连接', 'connect')
        this.RailIcon($r('app.media.ic_settings'), '设置', 'settings')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.expanded ? 4 : 10 })
      .alignItems(HorizontalAlign.Center)

      // 底部帮助
      Column() {
        this.RailIcon($r('app.media.ic_help'), '帮助', 'help')
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
      this.expanded = isHover
    })
    .animation({ duration: 200, curve: Curve.EaseInOut })
  }
}
