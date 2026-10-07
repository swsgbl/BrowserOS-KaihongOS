/**
 * P9-A: Chromium 风格浏览器 chrome 补全组件
 * - ThreeDotMenu: ⋮ 主菜单下拉（分组：新建标签页/新窗口 | 历史/书签/下载 | 设置/帮助 | 退出）
 * - OmniboxSuggestions: omnibox 聚焦建议下拉（历史+书签匹配）
 * - BookmarkBubble: 星标书签气泡（名称编辑 + 完成/删除）
 * 设计语言：#F1F3F4 chrome / #FFFFFF 卡 / #5F6368 图标 / #1A73E8 强调 / 分隔 #E0E0E0
 */

export interface SuggestItem {
  kind: string // 'history' | 'bookmark'
  title: string
  url: string
}

interface MenuEntry {
  icon: string
  label: string
  action: string
}

/** ⋮ 三点主菜单（自绘下拉，右上下锚定） */
@Component
export struct ThreeDotMenu {
  onAction: (action: string) => void = (action: string) => {}
  onClose: () => void = () => {}

  private readonly group1: MenuEntry[] = [
    { icon: '＋', label: '新建标签页', action: 'new_tab' },
    { icon: '⧉', label: '新窗口', action: 'new_window' }
  ]
  private readonly group2: MenuEntry[] = [
    { icon: '🕘', label: '历史', action: 'history' },
    { icon: '★', label: '书签', action: 'bookmarks' },
    { icon: '⭳', label: '下载', action: 'downloads' }
  ]
  private readonly group3: MenuEntry[] = [
    { icon: '⚙', label: '设置', action: 'settings' },
    { icon: '?', label: '帮助', action: 'help' }
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
        Divider().color('#E0E0E0').margin({ top: 4, bottom: 4 })
        this.MenuGroup(this.group2)
        Divider().color('#E0E0E0').margin({ top: 4, bottom: 4 })
        this.MenuGroup(this.group3)
        Divider().color('#E0E0E0').margin({ top: 4, bottom: 4 })
        Row() {
          Text('⏻')
            .fontSize(16)
            .fontColor('#C5221F')
            .width(28)
            .textAlign(TextAlign.Center)
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
      .backgroundColor('#FFFFFF')
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
        Text(entry.icon)
          .fontSize(16)
          .fontColor('#5F6368')
          .width(28)
          .textAlign(TextAlign.Center)
        Text(entry.label)
          .fontSize(14)
          .fontColor('#202124')
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
              Text(item.kind === 'bookmark' ? '★' : '🕘')
                .fontSize(14)
                .fontColor(item.kind === 'bookmark' ? '#F9AB00' : '#5F6368')
                .width(24)
                .textAlign(TextAlign.Center)
              Column() {
                Text(item.title.length > 0 ? item.title : item.url)
                  .fontSize(13)
                  .fontColor('#202124')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.url)
                  .fontSize(10)
                  .fontColor('#5F6368')
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
            .backgroundColor(index === 0 ? '#F0F6FF' : '#FFFFFF')
            .onClick(() => {
              this.onPick(item.url)
            })
          }, (item: SuggestItem, index: number) => item.kind + '_' + item.url + '_' + index)
        }
        .width(520)
        .constraintSize({ maxHeight: 360 })
        .padding(6)
        .borderRadius(12)
        .backgroundColor('#FFFFFF')
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
          .fontColor('#202124')
          .alignSelf(ItemAlign.Start)

        Text(this.url)
          .fontSize(10)
          .fontColor('#5F6368')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .alignSelf(ItemAlign.Start)

        Text('名称')
          .fontSize(11)
          .fontColor('#5F6368')
          .margin({ top: 10, bottom: 4 })
          .alignSelf(ItemAlign.Start)
        TextInput({ text: this.title })
          .width('100%')
          .height(36)
          .fontSize(13)
          .backgroundColor('#F1F3F4')
          .borderRadius(8)
          .onChange((value: string) => {
            this.onTitleChange(value)
          })

        Row() {
          if (this.editingExisting) {
            Button('删除')
              .fontSize(13)
              .height(34)
              .backgroundColor('#FFFFFF')
              .fontColor('#C5221F')
              .borderRadius(17)
              .border({ width: 1, color: '#DADCE0' })
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
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
      .margin({ top: 44, right: 52 })
    }
    .width('100%')
    .height('100%')
  }
}
