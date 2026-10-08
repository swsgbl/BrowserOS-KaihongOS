/**
 * P9-A: Chromium 风格浏览器 chrome 补全组件
 * - ThreeDotMenu: ⋮ 主菜单下拉（分组：新建标签页/新窗口 | 历史/书签/下载 | 设置/帮助 | 退出）
 * - OmniboxSuggestions: omnibox 聚焦建议下拉（历史+书签匹配）
 * - BookmarkBubble: 星标书签气泡（名称编辑 + 完成/删除）
 * 设计语言：#F1F3F4 chrome / #FFFFFF 卡 / #5F6368 图标 / #1A73E8 强调 / 分隔 #E0E0E0
 */

import { Palette } from '../common/Palette'

export interface SuggestItem {
  kind: string // 'history' | 'bookmark'
  title: string
  url: string
}

interface MenuEntry {
  icon: Resource
  label: string
  action: string
}

/** ⋮ 三点主菜单（自绘下拉，右上下锚定） */
@Component
export struct ThreeDotMenu {
  onAction: (action: string) => void = (action: string) => {}
  onClose: () => void = () => {}
  @StorageProp('darkMode') darkMode: boolean = false

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  private readonly group1: MenuEntry[] = [
    { icon: $r('app.media.ic_add'), label: '新建标签页', action: 'new_tab' },
    { icon: $r('app.media.ic_content_copy'), label: '新窗口', action: 'new_window' }
  ]
  private readonly group2: MenuEntry[] = [
    { icon: $r('app.media.ic_history'), label: '历史', action: 'history' },
    { icon: $r('app.media.ic_star_outline'), label: '书签', action: 'bookmarks' },
    { icon: $r('app.media.ic_download'), label: '下载', action: 'downloads' }
  ]
  private readonly group3: MenuEntry[] = [
    { icon: $r('app.media.ic_settings'), label: '设置', action: 'settings' },
    { icon: $r('app.media.ic_help'), label: '帮助', action: 'help' }
  ]

  build(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 全屏透明遮罩：点击任意处关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.onClose()
        })

      // 菜单卡（右上下锚定，宽 240）
      Column() {
        this.MenuGroup(this.group1)
        Divider().color(this.pal().border).margin({ top: 4, bottom: 4 })
        this.MenuGroup(this.group2)
        Divider().color(this.pal().border).margin({ top: 4, bottom: 4 })
        this.MenuGroup(this.group3)
        Divider().color(this.pal().border).margin({ top: 4, bottom: 4 })
        Row() {
          Image($r('app.media.ic_exit'))
            .width(18).height(18)
            .fillColor('#C5221F')
            .draggable(false)
          Text('退出')
            .fontSize(14)
            .fontColor('#C5221F')
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .borderRadius(6)
        .onClick(() => {
          this.onAction('exit')
        })
      }
      .width(240)
      .constraintSize({ maxHeight: 420 })
      .padding(6)
      .borderRadius(12)
      .backgroundColor(this.pal().surface)
      .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
      .margin({ top: 44, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MenuGroup(entries: MenuEntry[]): void {
    ForEach(entries, (entry: MenuEntry) => {
      Row() {
        Image(entry.icon)
          .width(18).height(18)
          .fillColor(this.pal().text2)
          .draggable(false)
        Text(entry.label)
          .fontSize(14)
          .fontColor(this.pal().text)
          .margin({ left: 4 })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .borderRadius(6)
      .onClick(() => {
        this.onAction(entry.action)
      })
    }, (entry: MenuEntry) => entry.action)
  }
}

/** omnibox 聚焦建议下拉（历史+书签匹配，图标+标题+URL） */
@Component
export struct OmniboxSuggestions {
  @StorageProp('darkMode') darkMode: boolean = false

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  items: SuggestItem[] = []
  onPick: (url: string) => void = (url: string) => {}
  onClose: () => void = () => {}

  build(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      // 透明遮罩截获外部点击（不压暗）
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.onClose()
        })

      if (this.items.length > 0) {
        Column() {
          ForEach(this.items, (item: SuggestItem, index: number) => {
            Row() {
              Image(item.kind === 'bookmark' ? $r('app.media.ic_star_filled') : $r('app.media.ic_history'))
                .width(16).height(16)
                .fillColor(item.kind === 'bookmark' ? '#F9AB00' : '#5F6368')
                .draggable(false)
              Column() {
                Text(item.title.length > 0 ? item.title : item.url)
                  .fontSize(13)
                  .fontColor(this.pal().text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.url)
                  .fontSize(10)
                  .fontColor(this.pal().text2)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 1 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .borderRadius(6)
            .backgroundColor(index === 0 ? this.pal().selected : this.pal().surface)
            .onClick(() => {
              this.onPick(item.url)
            })
          }, (item: SuggestItem, index: number) => item.kind + '_' + item.url + '_' + index)
        }
        .width(520)
        .constraintSize({ maxHeight: 360 })
        .padding(6)
        .borderRadius(12)
        .backgroundColor(this.pal().surface)
        .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
        .margin({ top: 50, left: 128 })
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** 星标书签气泡：名称可编辑 + 完成/删除 */
@Component
export struct BookmarkBubble {
  @StorageProp('darkMode') darkMode: boolean = false

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  title: string = ''
  url: string = ''
  editingExisting: boolean = false
  onTitleChange: (title: string) => void = (title: string) => {}
  onDone: () => void = () => {}
  onRemove: () => void = () => {}
  onClose: () => void = () => {}

  build(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#22000000')
        .onClick(() => {
          this.onClose()
        })

      Column() {
        Text(this.editingExisting ? '修改书签' : '已添加书签')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text)
          .alignSelf(ItemAlign.Start)

        Text(this.url)
          .fontSize(10)
          .fontColor(this.pal().text2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .alignSelf(ItemAlign.Start)

        Text('名称')
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ top: 10, bottom: 4 })
          .alignSelf(ItemAlign.Start)
        TextInput({ text: this.title })
          .width('100%')
          .height(36)
          .fontSize(13)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(8)
          .onChange((value: string) => {
            this.onTitleChange(value)
          })

        Row() {
          if (this.editingExisting) {
            Button('删除')
              .fontSize(13)
              .height(34)
              .backgroundColor(this.pal().surface)
              .fontColor('#C5221F')
              .borderRadius(17)
              .border({ width: 1, color: this.pal().border })
              .onClick(() => {
                this.onRemove()
              })
          }
          Blank()
          Button('完成')
            .fontSize(13)
            .height(34)
            .backgroundColor('#1A73E8')
            .fontColor('#FFFFFF')
            .borderRadius(17)
            .onClick(() => {
              this.onDone()
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width(280)
      .padding(14)
      .borderRadius(12)
      .backgroundColor(this.pal().surface)
      .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
      .margin({ top: 44, right: 52 })
    }
    .width('100%')
    .height('100%')
  }
}
