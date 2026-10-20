/**
 * P9-C3: 书签管理页 —— 列表（favicon+标题+URL+编辑/删除）
 */
import { BookmarkManager, ImportEntry } from '../service/BookmarkManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { router, promptAction } from '@kit.ArkUI'
import { Palette } from '../common/Palette'
import { picker, fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

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
  // P20-B: 搜索关键字（内存过滤 title/url,与 HistoryPage 同款交互）
  @State keyword: string = ''

  /** P20-B: 关键词内存过滤（大小写不敏感,匹配标题或 URL;空关键词=全量） */
  private filtered(): BookmarkRow[] {
    const kw = this.keyword.trim().toLowerCase()
    if (kw.length === 0) {
      return this.items
    }
    return this.items.filter((b: BookmarkRow) => {
      const t = b.title.length > 0 ? b.title : b.url
      return t.toLowerCase().indexOf(kw) >= 0 || b.url.toLowerCase().indexOf(kw) >= 0
    })
  }

  /** P32-A: Chrome 书签导入 —— 拾取器选 html → 读取 → Netscape 解析 → 批量导入 */
  private startImport(): void {
    // SDK 推荐带 context 构造（无参构造标注潜在失败风险）; getHostContext since 12
    const hostCtx = this.getUIContext().getHostContext()
    const docPicker = hostCtx !== undefined ? new picker.DocumentViewPicker(hostCtx) : new picker.DocumentViewPicker()
    const opts = new picker.DocumentSelectOptions()
    opts.fileSuffixFilters = ['html', 'htm']
    opts.maxSelectNumber = 1
    docPicker.select(opts).then((uris: Array<string>) => {
      if (uris.length === 0) {
        return
      }
      this.readAndImport(uris[0])
    }).catch((e: Object) => {
      // 用户取消拾取器 —— 静默（不提示不崩溃）
      console.info('BookmarksPage import picker dismissed: ' + e)
    })
  }

  private readAndImport(uri: string): void {
    let file: fs.File | null = null
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      file = null
      const text = util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer))
      const entries = this.parseNetscapeBookmarks(text)
      const result = BookmarkManager.importBookmarks(entries)
      this.reload()
      promptAction.showToast({ message: `导入 ${result.added} 条，跳过 ${result.skipped} 条重复`, duration: 2500 })
    } catch (e) {
      if (file !== null) {
        try {
          fs.closeSync(file)
        } catch (err) {
        }
      }
      console.error('BookmarksPage import read failed: ' + e)
      promptAction.showToast({ message: '导入失败：无法读取文件' })
    }
  }

  /** Netscape 书签格式: <A HREF="url" ...>title</A> —— 大小写不敏感,兼容单引号 */
  private parseNetscapeBookmarks(html: string): Array<ImportEntry> {
    const entries: Array<ImportEntry> = []
    const regex = /<a\s+href=(["'])(.*?)\1[^>]*>(.*?)<\/a>/gi
    let m: RegExpExecArray | null = regex.exec(html)
    while (m !== null) {
      const entry: ImportEntry = { url: this.decodeHtmlEntities(m[2]), title: this.decodeHtmlEntities(m[3]) }
      entries.push(entry)
      m = regex.exec(html)
    }
    console.info('BookmarksPage parseNetscapeBookmarks: entries=' + entries.length)
    return entries
  }

  /** 常见 HTML 实体解码（&amp; 最后,避免双重解码） */
  private decodeHtmlEntities(s: string): string {
    return s.replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&amp;/g, '&')
  }

  /** P14b: 书签订阅——列表页停留期间其它入口（星标气泡等）改动即时同步 */
  private onBookmarksChanged = (data: Object): void => {
    this.reload()
  }

  aboutToAppear(): void {
    EventBus.on(EventBusEvents.BOOKMARKS_CHANGED, this.onBookmarksChanged)
    this.reload()
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.BOOKMARKS_CHANGED, this.onBookmarksChanged)
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
        Image($rawfile('ic_back.svg'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(36)
          .accessibilityText('返回')
          .onClick(() => {
            router.back()
          })
        Text('书签')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text('导入')
          .fontSize(12)
          .fontColor('#1A73E8')
          .padding({ left: 8, right: 4 })
          .accessibilityText('导入书签')
          .onClick(() => {
            this.startImport()
          })
        Text(`${this.filtered().length} 条`)
          .fontSize(11)
          .fontColor(this.pal().text2)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.pal().surfaceAlt)

      // P20-B: 搜索框（HistoryPage 同款: ic_search + TextInput + 清除钮）
      Row() {
        Image($rawfile('ic_search.svg'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
        TextInput({ text: this.keyword, placeholder: '搜索书签' })
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().text2)
          .layoutWeight(1)
          .height(32)
          .fontSize(13)
          .type(InputType.Normal)
          .backgroundColor(Color.Transparent)
          .padding({ left: 4, right: 4 })
          .onChange((v: string) => {
            this.keyword = v
          })
        if (this.keyword.length > 0) {
          Button({ type: ButtonType.Normal }) {
            Image($rawfile('ic_close.svg'))
              .width(14).height(14)
              .fillColor(this.pal().text2)
              .draggable(false)
          }
          .width(26)
          .height(26)
          .backgroundColor(Color.Transparent)
          .accessibilityText('清除搜索')
          .onClick(() => {
            this.keyword = ''
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(18)
      .backgroundColor(this.pal().surface)
      .border({ width: 1, color: this.pal().border })
      .margin({ left: 12, right: 12, top: 10 })

      if (this.items.length === 0) {
        Column() {
          Image($rawfile('ic_star_outline.svg'))
            .width(36).height(36)
            .fillColor('#DADCE0')
            .draggable(false)
          Text('暂无书签 —— 在页面点击地址栏旁星标添加')
            .fontSize(13)
            .fontColor(this.pal().text2)
            .margin({ top: 8 })
        }
        .width('100%')
        .margin({ top: 100 })
      } else if (this.filtered().length === 0) {
        // P20-B: 有关键词但无命中
        Column() {
          Text('无匹配书签')
            .fontSize(13)
            .fontColor(this.pal().text2)
            .margin({ top: 60 })
        }
        .width('100%')
      } else {
        Scroll() {
          Column() {
            ForEach(this.filtered(), (b: BookmarkRow) => {
              Column() {
                Row() {
                  Image($rawfile('ic_star_filled.svg'))
                    .width(14).height(14)
                    .fillColor('#F9AB00')
                    .draggable(false)
                    .margin({ left: 6 })
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
