/**
 * P11c: 通用右键菜单卡组件(项目首批 ContextMenu)
 * 两条挂载路径:
 * 1) bindContextMenu(builder, ResponseType.RightClick) —— 系统弹窗(标签条/仪表盘),
 *    系统负责显示/隐藏与锚定,x/y 传 -1(只渲染卡体)
 * 2) Web.onContextMenuShow 拦截 —— 手动覆盖层(网页右键),x/y 定位 + 透明遮罩
 * 行规格: icon18 + 文字13 + 快捷键11(右灰) / hover 浅#F0F1F3 深#3C4043 / 禁用 40% / 卡宽 240
 */
import { Palette } from '../common/Palette'

export interface CtxEntry {
  icon?: Resource
  label: string
  shortcut?: string
  enabled: boolean
  divider: boolean
  onTap?: () => void
}

export function ctxDivider(): CtxEntry {
  return { label: '', enabled: false, divider: true }
}

@Component
export struct ContextMenu {
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44
  /** -1 = 系统弹窗模式(无遮罩无定位,仅卡体);>=0 = 手动覆盖层模式 */
  x: number = -1
  y: number = -1
  entries: CtxEntry[] = []
  onClose: () => void = () => {}
  @State hoverKey: string = ''

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  private hoverBg(): string {
    return this.darkMode ? '#3C4043' : '#F0F1F3'
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('ContextMenu theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    if (this.x >= 0) {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }

      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.onClose()
          })
        Column() {
          this.MenuCard()
        }
        .position({ x: this.x, y: this.y })
      }
      .width('100%')
      .height('100%')
    } else {
      this.MenuCard()
    }
  }

  @Builder
  MenuCard(): void {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.entries, (e: CtxEntry, i: number) => {
            if (e.divider) {
              Divider()
                .color(this.pal().border)
                .margin({ top: 4, bottom: 4 })
            } else {
              Row() {
                if (e.icon) {
                  Image(e.icon)
                    .width(18).height(18)
                    .fillColor(this.pal().text2)
                    .draggable(false)
                } else {
                  Column().width(18)
                }
                Text(e.label)
                  .fontSize(13)
                  .fontColor(this.pal().text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (e.shortcut && e.shortcut.length > 0) {
                  Text(e.shortcut)
                    .fontSize(11)
                    .fontColor(this.pal().text2)
                    .margin({ left: 8 })
                }
              }
              .width('100%')
              .height(36)
              .borderRadius(6)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.hoverKey === e.label + '_' + i && e.enabled ? this.hoverBg() : Color.Transparent)
              .opacity(e.enabled ? 1 : 0.4)
              .onHover((isHover: boolean) => {
                this.hoverKey = isHover ? e.label + '_' + i : ''
              })
              .onClick(() => {
                if (e.enabled && e.onTap) {
                  e.onTap()
                }
                this.onClose()
              })
            }
          }, (e: CtxEntry, i: number) => e.label + '_' + i)
        }
        .width('100%')
      }
      .align(Alignment.Start)
      .constraintSize({ maxHeight: 400 })
    }
    .width(240)
    .padding(6)
    .borderRadius(12)
    .backgroundColor(this.pal().surface)
    .shadow({ radius: 16, color: '#44000000', offsetX: 0, offsetY: 4 })
  }
}
