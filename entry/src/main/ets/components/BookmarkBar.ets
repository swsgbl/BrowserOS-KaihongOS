/**
 * P11d: 书签条 —— 工具栏与标签条之下的 Chromium 风格书签栏(仅新标签页/驾驶舱显示)
 * - 高 32,横向 Scroll,pill 项(ic_globe 14 染灰 + 书签名 12px)
 * - 点击 pill = 新标签打开该书签;右端「全部书签」入口 → BookmarksPage
 * 设计语言沿用 Palette(surface/surfaceAlt/text/text2/border)
 */
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'
import { BookmarkManager } from '../service/BookmarkManager'

interface BookmarkPill {
  id: string
  url: string
  title: string
}

@Component
export struct BookmarkBar {
  /** p10a: AppStorage('darkMode') 消费 */
  @StorageProp('darkMode') darkMode: boolean = false
  /** shell 注入的书签数据(getAllBookmarks 已按 createdAt 降序) */
  bookmarks: BookmarkPill[] = []
  onOpenBookmark: (url: string) => void = (url: string) => {}

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  build(): void {
    Row() {
      Scroll() {
        Row() {
          if (this.bookmarks.length === 0) {
            Text('暂无书签 —— 点星标收藏当前页')
              .fontSize(11)
              .fontColor(this.pal().text2)
              .padding({ left: 4, right: 8 })
          }
          ForEach(this.bookmarks, (bm: BookmarkPill) => {
            Row() {
              Image($r('app.media.ic_globe'))
                .width(14).height(14)
                .fillColor(this.pal().text2)
                .draggable(false)
              Text(bm.title.length > 0 ? bm.title : bm.url)
                .fontSize(12)
                .fontColor(this.pal().text)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 120 })
                .margin({ left: 6 })
            }
            .height(24)
            .padding({ left: 10, right: 10 })
            .borderRadius(12)
            .backgroundColor(this.pal().surfaceAlt)
            .margin({ right: 6 })
            .onClick(() => {
              this.onOpenBookmark(bm.url)
            })
          }, (bm: BookmarkPill) => bm.id)
        }
        .height(32)
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)

      // 右端「全部书签」入口
      Row() {
        Image($r('app.media.ic_folder'))
          .width(14).height(14)
          .fillColor(this.pal().text2)
          .draggable(false)
        Text('全部书签 ' + this.bookmarks.length)
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ left: 4 })
      }
      .height(24)
      .padding({ left: 10, right: 10 })
      .borderRadius(12)
      .margin({ left: 8 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/BookmarksPage' })
      })
    }
    .width('100%')
    .height(32)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
    .alignItems(VerticalAlign.Center)
  }
}
