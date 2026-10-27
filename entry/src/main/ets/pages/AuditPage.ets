/**
 * P54: 审计事件列表页 —— AuditEventBus 环形缓冲（最近 200 条）倒序渲染。
 * - 筛选：事件类型（工具/导航/标签/截图）+ 状态（成功/失败）
 * - 行点击展开脱敏明细（redactedInput/redactedOutput/errorCode）
 * - 实时刷新：订阅 AuditEventBus 新事件
 */
import { AuditEventBus, AuditEvent, AuditEventType } from '../service/AuditEventBus'
import { I18n } from '../common/I18n'
import { Palette } from '../common/Palette'
import { router } from '@kit.ArkUI'

/** 筛选维度 */
interface TypeFilter {
  id: string
  label: string
}

@Entry
@Component
struct AuditPage {
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false
  @State themeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  onThemeFlip(): void {
    this.themeVersion++
  }

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State events: AuditEvent[] = []
  @State expandedSeq: number = -1
  @State typeFilter: string = 'all'
  @State statusFilter: string = 'all'
  private unsub: (() => void) | null = null

  aboutToAppear(): void {
    this.reload()
    this.unsub = AuditEventBus.subscribe((e: AuditEvent) => {
      this.reload()
    })
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub()
      this.unsub = null
    }
  }

  private reload(): void {
    this.events = AuditEventBus.getRecent(200)
  }

  /** 类型筛选标签组 */
  private typeFilters(): TypeFilter[] {
    return [
      { id: 'all', label: I18n.t('auFilterAll') },
      { id: 'tool', label: I18n.t('auFilterTool') },
      { id: 'nav', label: I18n.t('auFilterNav') },
      { id: 'tab', label: I18n.t('auFilterTab') },
      { id: 'shot', label: I18n.t('auFilterShot') }
    ]
  }

  /** 事件归类到筛选桶 */
  private bucketOf(ev: AuditEvent): string {
    if (ev.eventType === AuditEventType.TOOL_START || ev.eventType === AuditEventType.TOOL_END) {
      return 'tool'
    }
    if (ev.eventType === AuditEventType.NAVIGATION) {
      return 'nav'
    }
    if (ev.eventType === AuditEventType.TAB_CREATED || ev.eventType === AuditEventType.TAB_CLOSED) {
      return 'tab'
    }
    if (ev.eventType === AuditEventType.SCREENSHOT) {
      return 'shot'
    }
    return 'other'
  }

  private visibleEvents(): AuditEvent[] {
    return this.events.filter((ev: AuditEvent): boolean => {
      if (this.typeFilter !== 'all' && this.bucketOf(ev) !== this.typeFilter) {
        return false
      }
      if (this.statusFilter === 'ok' && ev.status !== 'ok' && ev.status !== 'running') {
        return false
      }
      if (this.statusFilter === 'error' && ev.status !== 'error') {
        return false
      }
      return true
    })
  }

  /** 事件类型短标 */
  private typeLabel(ev: AuditEvent): string {
    switch (ev.eventType) {
      case AuditEventType.TOOL_START:
        return '▶ ' + ev.toolName
      case AuditEventType.TOOL_END:
        return '■ ' + ev.toolName
      case AuditEventType.NAVIGATION:
        return '➤ ' + (ev.toolName.length > 0 ? ev.toolName : 'navigation')
      case AuditEventType.TAB_CREATED:
        return '+ tab'
      case AuditEventType.TAB_CLOSED:
        return '− tab'
      case AuditEventType.SCREENSHOT:
        return '▣ screenshot'
      case AuditEventType.SESSION_STATUS:
        return '◇ session'
      default:
        return ev.eventType
    }
  }

  /** HH:mm:ss */
  private timeLabel(ts: number): string {
    const d = new Date(ts)
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n)
    return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  }

  private statusColor(ev: AuditEvent): string {
    if (ev.status === 'ok') {
      return '#137333'
    }
    if (ev.status === 'error') {
      return '#C5221F'
    }
    return '#B06000'
  }

  build(): void {
    Column() {
      // locale/theme 渲染锚
      if (this.localeVersion < 0 || this.themeVersion < 0) {
        Text('').fontSize(0)
      }
      // 顶栏
      Row() {
        Button({ type: ButtonType.Normal }) {
          Image($rawfile('ic_back.svg'))
            .width(20).height(20)
            .fillColor(this.pal().text)
            .draggable(false)
        }
        .width(40).height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back()
        })
        Column() {
          Text(I18n.t('auTitle'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().text)
          Text(I18n.t('auSub'))
            .fontSize(11)
            .fontColor(this.pal().text2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 12 })

      // 筛选行
      Row({ space: 8 }) {
        Row() {
          Row({ space: 6 }) {
            ForEach(this.typeFilters(), (f: TypeFilter) => {
              Text(f.label)
                .fontSize(12)
                .fontColor(this.typeFilter === f.id ? '#FFFFFF' : this.pal().text)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(12)
                .backgroundColor(this.typeFilter === f.id ? '#1A73E8' : this.pal().surfaceAlt)
                .onClick(() => {
                  this.typeFilter = f.id
                })
            }, (f: TypeFilter) => f.id)
          }
        }
        .layoutWeight(1)

        // 状态筛选
        Row() {
          Text(this.statusFilter === 'all' ? I18n.t('auStatusAll') :
            (this.statusFilter === 'ok' ? I18n.t('auStatusOk') : I18n.t('auStatusErr')))
            .fontSize(12)
            .fontColor(this.pal().text)
          Text('▾')
            .fontSize(12)
            .fontColor(this.pal().text2)
            .margin({ left: 4 })
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(12)
        .backgroundColor(this.pal().surfaceAlt)
        .onClick(() => {
          // all -> ok -> error 循环
          if (this.statusFilter === 'all') {
            this.statusFilter = 'ok'
          } else if (this.statusFilter === 'ok') {
            this.statusFilter = 'error'
          } else {
            this.statusFilter = 'all'
          }
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 8 })

      Divider().color(this.pal().border)

      // 事件列表
      if (this.visibleEvents().length === 0) {
        Column() {
          Text(I18n.t('auEmpty'))
            .fontSize(14)
            .fontColor(this.pal().text2)
            .margin({ top: 80 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
      } else {
        Row() {
          Column() {
            ForEach(this.visibleEvents(), (ev: AuditEvent) => {
              Column() {
                // 摘要行
                Row({ space: 8 }) {
                  Text(this.typeLabel(ev))
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.pal().text)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (ev.status.length > 0) {
                    Text(ev.status)
                      .fontSize(10)
                      .fontColor(this.statusColor(ev))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(8)
                      .backgroundColor(this.pal().surfaceAlt)
                  }
                  Text(this.timeLabel(ev.timestamp))
                    .fontSize(11)
                    .fontColor(this.pal().text2)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 6 })

                // 次行：会话 + tab
                Row({ space: 8 }) {
                  Text(ev.sessionId === 'internal-agent'
                    ? (I18n.t('auSession') + ': ' + I18n.t('auInternal'))
                    : (I18n.t('auSession') + ': ' + ev.sessionId.substring(0, 12)))
                    .fontSize(10)
                    .fontColor(this.pal().text2)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  if (ev.tabId.length > 0) {
                    Text('tab: ' + ev.tabId.substring(0, 16))
                      .fontSize(10)
                      .fontColor(this.pal().text2)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, bottom: 6 })

                // 展开明细
                if (this.expandedSeq === ev.seq) {
                  Column({ space: 4 }) {
                    if (ev.redactedInput.length > 0) {
                      Text(I18n.t('auDetailIn') + ': ' + ev.redactedInput)
                        .fontSize(11)
                        .fontColor(this.pal().text)
                        .width('100%')
                    }
                    if (ev.redactedOutput.length > 0) {
                      Text(I18n.t('auDetailOut') + ': ' + ev.redactedOutput)
                        .fontSize(11)
                        .fontColor(this.pal().text)
                        .width('100%')
                    }
                    if (ev.errorCode.length > 0) {
                      Text(I18n.t('auDetailErr') + ': ' + ev.errorCode)
                        .fontSize(11)
                        .fontColor('#C5221F')
                        .width('100%')
                    }
                    if (ev.durationMs > 0) {
                      Text(I18n.t('auDuration') + ': ' + ev.durationMs + 'ms')
                        .fontSize(11)
                        .fontColor(this.pal().text2)
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, bottom: 10 })
                  .border({
                    width: { left: 2 },
                    color: this.pal().border
                  })
                  .margin({ left: 14, right: 14, bottom: 6 })
                }

                Divider().color(this.pal().border).opacity(0.5)
              }
              .onClick(() => {
                // 行点击展开/收起明细
                this.expandedSeq = this.expandedSeq === ev.seq ? -1 : ev.seq
              })
            }, (ev: AuditEvent) => `${ev.seq}`)
          }
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surface)
  }
}
