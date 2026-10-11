/**
 * P23a: 定时任务页 —— 列表（名称/频率/开关/上次运行时间/结果摘要）+ 新建面板
 */
import { ScheduleManager, ScheduleTask } from '../service/ScheduleManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'

/** 列表行视图模型（深拷贝，避免直接引用 manager 内部对象） */
interface TaskRow {
  id: string
  name: string
  prompt: string
  targetUrl: string
  interval: string
  timeOfDay: string
  enabled: boolean
  lastRunAt: number
  lastResult: string
}

@Entry
@Component
struct ScheduledTasksPage {
  @StorageProp('darkMode') darkMode: boolean = false
  @State tasks: TaskRow[] = []
  @State showNewPanel: boolean = false
  // 新建面板表单
  @State newName: string = ''
  @State newPrompt: string = ''
  @State newUrl: string = ''
  @State newInterval: string = 'daily'
  @State newTime: string = '09:00'
  @State formError: string = ''

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  private onSchedulesChanged = (data: Object): void => {
    this.reload()
  }

  aboutToAppear(): void {
    EventBus.on(EventBusEvents.SCHEDULES_CHANGED, this.onSchedulesChanged)
    this.reload()
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.SCHEDULES_CHANGED, this.onSchedulesChanged)
  }

  private reload(): void {
    const rows: TaskRow[] = []
    const all = ScheduleManager.getTasks()
    for (const t of all) {
      const row: TaskRow = {
        id: t.id, name: t.name, prompt: t.prompt, targetUrl: t.targetUrl,
        interval: t.interval, timeOfDay: t.timeOfDay, enabled: t.enabled,
        lastRunAt: t.lastRunAt, lastResult: t.lastResult
      }
      rows.push(row)
    }
    this.tasks = rows
    console.info('ScheduledTasksPage loaded: ' + rows.length)
  }

  /** 频率文案：hourly=每小时 / daily=每天 HH:mm / weekly=每周一 HH:mm */
  private freqText(t: TaskRow): string {
    if (t.interval === 'hourly') {
      return '每小时'
    }
    const tod = this.validTime(t.timeOfDay) ? t.timeOfDay : '09:00'
    if (t.interval === 'daily') {
      return '每天 ' + tod
    }
    return '每周一 ' + tod
  }

  private validTime(s: string): boolean {
    return /^(\d{1,2}):(\d{2})$/.test(s.trim())
  }

  private fmtTime(ts: number): string {
    if (ts <= 0) {
      return '从未'
    }
    const d = new Date(ts)
    const p = (n: number): string => n < 10 ? '0' + n : '' + n
    return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes())
  }

  private saveNew(): void {
    const name = this.newName.trim()
    const prompt = this.newPrompt.trim()
    if (name.length === 0 || prompt.length === 0) {
      this.formError = '名称与任务描述不能为空'
      return
    }
    let interval = this.newInterval
    let time = this.newTime.trim()
    if (interval === 'hourly') {
      time = ''
    } else if (!this.validTime(time)) {
      this.formError = '时间格式应为 HH:mm（如 09:00）'
      return
    }
    ScheduleManager.addTask(name, prompt, this.newUrl.trim(), interval, time)
    this.showNewPanel = false
    this.newName = ''
    this.newPrompt = ''
    this.newUrl = ''
    this.newInterval = 'daily'
    this.newTime = '09:00'
    this.formError = ''
    this.reload()
  }

  build(): void {
    Column() {
      // 头部
      Row() {
        Image($r('app.media.ic_back'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
          .accessibilityText('返回')
          .onClick(() => {
            router.back()
          })
        Text('定时任务')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text(this.tasks.length + ' 个')
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ right: 12 })
        Text('新建')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A73E8')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.pal().selected)
          .borderRadius(14)
          .onClick(() => {
            this.showNewPanel = true
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.pal().surfaceAlt)

      // 新建面板
      if (this.showNewPanel) {
        Column() {
          Text('新建定时任务')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal().text)
            .alignSelf(ItemAlign.Start)

          Text('名称')
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 10, bottom: 4 })
            .alignSelf(ItemAlign.Start)
          TextInput({ text: this.newName, placeholder: '如：早间新闻摘要' })
            .width('100%')
            .height(36)
            .fontSize(13)
            .fontColor(this.pal().text)
            .placeholderColor(this.pal().text2)
            .backgroundColor(this.pal().surfaceAlt)
            .borderRadius(8)
            .onChange((v: string) => {
              this.newName = v
            })

          Text('任务描述（发给代理的提示词）')
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 10, bottom: 4 })
            .alignSelf(ItemAlign.Start)
          TextArea({ text: this.newPrompt, placeholder: '如：打开页面并总结今日头条新闻，输出 3 条要点' })
            .width('100%')
            .height(64)
            .fontSize(13)
            .fontColor(this.pal().text)
            .placeholderColor(this.pal().text2)
            .backgroundColor(this.pal().surfaceAlt)
            .borderRadius(8)
            .onChange((v: string) => {
              this.newPrompt = v
            })

          Text('目标 URL（可空）')
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 10, bottom: 4 })
            .alignSelf(ItemAlign.Start)
          TextInput({ text: this.newUrl, placeholder: 'https://example.com' })
            .width('100%')
            .height(36)
            .fontSize(13)
            .fontColor(this.pal().text)
            .placeholderColor(this.pal().text2)
            .backgroundColor(this.pal().surfaceAlt)
            .borderRadius(16)
            .onChange((v: string) => {
              this.newUrl = v
            })

          Text('频率')
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 10, bottom: 4 })
            .alignSelf(ItemAlign.Start)
          Row() {
            this.IntervalPill('每小时', 'hourly')
            this.IntervalPill('每天', 'daily')
            this.IntervalPill('每周一', 'weekly')
          }
          .width('100%')

          if (this.newInterval === 'daily' || this.newInterval === 'weekly') {
            Text('时间（HH:mm）')
              .fontSize(11)
              .fontColor(this.pal().text2)
              .margin({ top: 10, bottom: 4 })
              .alignSelf(ItemAlign.Start)
            TextInput({ text: this.newTime, placeholder: '09:00' })
              .width('100%')
              .height(36)
              .fontSize(13)
              .fontColor(this.pal().text)
              .placeholderColor(this.pal().text2)
              .backgroundColor(this.pal().surfaceAlt)
              .borderRadius(8)
              .onChange((v: string) => {
                this.newTime = v
              })
          }

          if (this.formError.length > 0) {
            Text(this.formError)
              .fontSize(11)
              .fontColor('#C5221F')
              .margin({ top: 8 })
              .alignSelf(ItemAlign.Start)
          }

          Row() {
            Button('取消')
              .fontSize(13)
              .height(34)
              .backgroundColor(this.pal().surface)
              .fontColor(this.pal().text2)
              .borderRadius(17)
              .border({ width: 1, color: this.pal().border })
              .onClick(() => {
                this.showNewPanel = false
                this.formError = ''
              })
            Blank()
            Button('保存')
              .fontSize(13)
              .height(34)
              .backgroundColor('#1A73E8')
              .fontColor('#FFFFFF')
              .borderRadius(17)
              .onClick(() => {
                this.saveNew()
              })
          }
          .width('100%')
          .margin({ top: 14 })
        }
        .width('100%')
        .padding(14)
        .borderRadius(12)
        .backgroundColor(this.pal().surface)
        .border({ width: 1, color: this.pal().border })
        .margin({ left: 12, right: 12, top: 10 })
        .alignItems(HorizontalAlign.Start)
      }

      // 空态 / 列表
      if (this.tasks.length === 0) {
        Column() {
          Image($r('app.media.ic_schedule'))
            .width(36).height(36)
            .fillColor('#DADCE0')
            .draggable(false)
          Text('暂无定时任务 —— 点击右上角新建')
            .fontSize(13)
            .fontColor(this.pal().text2)
            .margin({ top: 8 })
        }
        .width('100%')
        .margin({ top: 100 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.tasks, (t: TaskRow) => {
              Column() {
                Row() {
                  Column() {
                    Text(t.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.pal().text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.freqText(t) + ' · 上次 ' + this.fmtTime(t.lastRunAt))
                      .fontSize(11)
                      .fontColor(this.pal().text2)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: t.enabled })
                    .width(40)
                    .height(22)
                    .onChange((isOn: boolean) => {
                      ScheduleManager.setEnabled(t.id, isOn)
                    })
                }
                .width('100%')

                if (t.lastResult.length > 0) {
                  Text(t.lastResult)
                    .fontSize(11)
                    .fontColor(this.pal().text2)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 6 })
                    .padding({ left: 8 })
                    .border({ width: { left: 2 }, color: '#DADCE0' })
                }

                Row() {
                  Blank()
                  Text('立即运行')
                    .fontSize(12)
                    .fontColor('#1A73E8')
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .onClick(() => {
                      ScheduleManager.runNow(t.id)
                      this.reload()
                    })
                  Text('删除')
                    .fontSize(12)
                    .fontColor('#C5221F')
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .onClick(() => {
                      ScheduleManager.removeTask(t.id)
                      this.reload()
                    })
                }
                .width('100%')
                .margin({ top: 4 })

                Divider().color('#F1F3F4').margin({ top: 8 })
              }
              .padding({ top: 10, bottom: 4 })
            }, (t: TaskRow) => t.id + '_' + t.enabled + '_' + t.lastRunAt)
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

  /** 频率单选 pill */
  @Builder
  IntervalPill(label: string, value: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.newInterval === value ? '#1A73E8' : this.pal().text2)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.newInterval === value ? this.pal().selected : this.pal().surfaceAlt)
      .borderRadius(14)
      .margin({ right: 8 })
      .onClick(() => {
        this.newInterval = value
      })
  }
}
