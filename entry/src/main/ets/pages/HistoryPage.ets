/**
 * P9-C2: 历史页（ref4 风格）—— 搜索框 + 按日期分组列表（favicon+标题+URL+时间）
 * + agent 会话条目带 ▶ 回放直达 SessionPlayerPage
 */
import { HistoryManager, HistoryEntry } from '../service/HistoryManager'
import { SessionManager } from '../service/SessionManager'
import { SessionRecord } from '../model/SessionRecord'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'

interface GroupedEntry {
  key: string
  group: string
  entry: HistoryEntry
}

@Entry
@Component
struct HistoryPage {
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') darkMode: boolean = false

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State keyword: string = ''
  @State entries: HistoryEntry[] = []
  @State grouped: GroupedEntry[] = []
  @State sessions: SessionRecord[] = []

  aboutToAppear(): void {
    this.reload()
  }

  private reload(): void {
    this.entries = HistoryManager.getAllHistory(200)
    this.sessions = SessionManager.getSessionList()
    // P9r: 磁盘会话异步就绪后再刷新一次（冷启动首次渲染可能先拿到空列表）
    SessionManager.getSessionListAsync().then((list: SessionRecord[]) => {
      this.sessions = list
      console.info('HistoryPage sessions refreshed: ' + list.length)
    })
    if (this.keyword.trim().length > 0) {
      const kw = this.keyword.trim().toLowerCase()
      this.entries = this.entries.filter((e: HistoryEntry) =>
        e.url.toLowerCase().includes(kw) || (e.title || '').toLowerCase().includes(kw))
    }
    // 预计算日期分组（ForEach 内不能写命令式赋值）
    const grouped: GroupedEntry[] = []
    let lastGroup = ''
    for (const e of this.entries) {
      const g = this.dateGroup(e.timestamp)
      if (g !== lastGroup) {
        lastGroup = g
        grouped.push({ key: g + '_' + e.timestamp + '_head', group: g, entry: e })
      } else {
        grouped.push({ key: g + '_' + e.timestamp, group: '', entry: e })
      }
    }
    this.grouped = grouped
    console.info('HistoryPage loaded: entries=' + this.entries.length + ' sessions=' + this.sessions.length)
  }

  private dateGroup(ts: number): string {
    const d = new Date(ts)
    const now = new Date()
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    if (ts >= todayStart) {
      return '今天'
    }
    if (ts >= todayStart - 86400000) {
      return '昨天'
    }
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`
  }

  private timeOf(ts: number): string {
    const d = new Date(ts)
    const h = d.getHours().toString().padStart(2, '0')
    const m = d.getMinutes().toString().padStart(2, '0')
    return `${h}:${m}`
  }

  build(): void {
    Column() {
      // 顶栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(36)
          .onClick(() => {
            router.back()
          })
        Text('历史记录')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text(`${this.entries.length} 条`)
          .fontSize(11)
          .fontColor(this.pal().text2)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.pal().surfaceAlt)

      // 搜索框
      Row() {
        Text('🔍')
          .fontSize(13)
          .width(28)
          .textAlign(TextAlign.Center)
        TextInput({ text: this.keyword, placeholder: '搜索历史记录' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor(Color.Transparent)
          .onChange((v: string) => {
            this.keyword = v
            this.reload()
          })
      }
      .width('94%')
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.pal().surfaceAlt)
      .margin({ top: 12 })

      // 列表
      Scroll() {
        Column() {
          // agent 会话组
          if (this.sessions.length > 0) {
            Text('代理会话')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().text2)
              .width('100%')
              .margin({ top: 16, bottom: 6 })

            ForEach(this.sessions, (s: SessionRecord) => {
              Row() {
                Column() {
                  Text('A')
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                }
                .width(24)
                .height(24)
                .borderRadius(6)
                .backgroundColor('#1A73E8')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Column() {
                  Text(`代理 ${s.agentId.substring(0, 14)}…`)
                    .fontSize(13)
                    .fontColor(this.pal().text)
                    .maxLines(1)
                  Text(`${s.operationLogs.length} 步操作 · ${this.timeOf(s.startTime)}`)
                    .fontSize(10)
                    .fontColor(this.pal().text2)
                    .margin({ top: 1 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 10 })

                Text('▶ 回放')
                  .fontSize(12)
                  .fontColor('#1A73E8')
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .borderRadius(12)
                  .backgroundColor(this.pal().selected)
                  .onClick(() => {
                    console.info('HistoryPage replay: ' + s.sessionId)
                    router.pushUrl({
                      url: 'pages/SessionPlayerPage',
                      params: { 'sessionId': s.sessionId } as Record<string, Object>
                    })
                  })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
            }, (s: SessionRecord) => s.sessionId)
          }

          // 浏览历史（按日期分组）
          if (this.entries.length === 0) {
            Column() {
              Text('🕘')
                .fontSize(36)
                .fontColor('#DADCE0')
              Text('暂无历史记录')
                .fontSize(13)
                .fontColor(this.pal().text2)
                .margin({ top: 8 })
            }
            .width('100%')
            .margin({ top: 80 })
          } else {
            ForEach(this.grouped, (g: GroupedEntry, idx: number) => {
              Column() {
                if (g.group.length > 0) {
                  Text(g.group)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.pal().text2)
                    .width('100%')
                    .margin({ top: 14, bottom: 6 })
                }
                Row() {
                  Image($r('app.media.ic_public'))
                    .width(14).height(14)
                    .fillColor('#9AA0A6')
                    .draggable(false)
                    .margin({ left: 5 })
                  Column() {
                    Text(g.entry.title && g.entry.title.length > 0 ? g.entry.title : g.entry.url)
                      .fontSize(13)
                      .fontColor(this.pal().text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(g.entry.url)
                      .fontSize(10)
                      .fontColor(this.pal().text2)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 1 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(this.timeOf(g.entry.timestamp))
                    .fontSize(11)
                    .fontColor('#9AA0A6')
                    .margin({ left: 8 })
                }
                .width('100%')
                .padding({ top: 7, bottom: 7 })
              }
            }, (g: GroupedEntry, idx: number) => g.key)
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 30 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(this.pal().surface)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surface)
  }
}
