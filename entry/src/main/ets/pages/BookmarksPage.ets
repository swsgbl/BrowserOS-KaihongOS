/**
 * P9-C3: 书签管理页 —— 列表（favicon+标题+URL+编辑/删除）
 */
import { BookmarkManager } from '../service/BookmarkManager'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'

interface BookmarkRow {
  id: string
  url: string
  title: string
  createdAt: number
}

@Entry
@Component
struct BookmarksPage {
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') darkMode: boolean = false

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State items: BookmarkRow[] = []
  @State editingId: string = ''
  @State editTitle: string = ''

  aboutToAppear(): void {
    this.reload()
  }

  private reload(): void {
    this.items = BookmarkManager.getAllBookmarks().map((b) => {
      const row: BookmarkRow = { id: b.id, url: b.url, title: b.title, createdAt: b.createdAt }
      return row
    })
    console.info('BookmarksPage loaded: ' + this.items.length)
  }

  build(): void {
    Column() {
      Row() {
        Text('←')
          .fontSize(18)
          .fontColor(this.pal().text2)
          .width(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back()
          })
        Text('书签')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text(`${this.items.length} 条`)
          .fontSize(11)
          .fontColor(this.pal().text2)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.pal().surfaceAlt)

      if (this.items.length === 0) {
        Column() {
          Text('☆')
            .fontSize(36)
            .fontColor('#DADCE0')
          Text('暂无书签 —— 在页面点击地址栏旁星标添加')
            .fontSize(13)
            .fontColor(this.pal().text2)
            .margin({ top: 8 })
        }
        .width('100%')
        .margin({ top: 100 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.items, (b: BookmarkRow) => {
              Column() {
                Row() {
                  Text('★')
                    .fontSize(13)
                    .fontColor('#F9AB00')
                    .width(26)
                    .textAlign(TextAlign.Center)
                  if (this.editingId === b.id) {
                    TextInput({ text: this.editTitle }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
                      .layoutWeight(1)
                      .height(32)
                      .fontSize(13)
                      .backgroundColor(this.pal().surfaceAlt)
                      .borderRadius(6)
                      .onChange((v: string) => { this.editTitle = v })
                    Text('保存')
                      .fontSize(12)
                      .fontColor('#1A73E8')
                      .padding({ left: 10 })
                      .onClick(() => {
                        BookmarkManager.updateBookmark(b.id, undefined, this.editTitle)
                        this.editingId = ''
                        this.reload()
                      })
                  } else {
                    Column() {
                      Text(b.title.length > 0 ? b.title : b.url)
                        .fontSize(13)
                        .fontColor(this.pal().text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(b.url)
                        .fontSize(10)
                        .fontColor(this.pal().text2)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 1 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Text('编辑')
                      .fontSize(12)
                      .fontColor('#1A73E8')
                      .margin({ left: 8 })
                      .onClick(() => {
                        this.editingId = b.id
                        this.editTitle = b.title
                      })
                  }
                  Text('删除')
                    .fontSize(12)
                    .fontColor('#C5221F')
                    .margin({ left: 10 })
                    .onClick(() => {
                      BookmarkManager.removeBookmark(b.id)
                      this.reload()
                    })
                }
                .width('100%')
                .padding({ top: 9, bottom: 9 })
                Divider().color('#F1F3F4')
              }
            }, (b: BookmarkRow) => b.id + '_' + b.title)
          }
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 30 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surface)
  }
}
