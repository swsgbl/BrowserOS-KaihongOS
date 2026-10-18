/**
 * P35-A: JTBD 调查页（对标上游 jtbd-agent 屏：Welcome → 对话式 3 问 → ThankYou）
 * - Welcome 卡：Sparkles 橙圆 + Share Your Experience + 原文副标题 + Start Survey 大钮
 * - 对话式 3 问（写死中文）：你主要用 BrowserOS 做什么 / 最想要什么改进 / 愿意推荐吗
 * - 答案存 Preferences jtbd_store.answers（JSON 数组）并标记 surveyTaken
 * - 完成卡：感谢 + 返回浏览器（router.back）
 */
import { router } from '@kit.ArkUI'
import { preferences } from '@kit.ArkData'
import { Palette } from '../common/Palette'

class SurveyMessage {
  role: string = '' // 'user' | 'agent'
  text: string = ''
  constructor(role: string, text: string) {
    this.role = role
    this.text = text
  }
}

/** P35-A: jtbd_store 读写（与 AgentSidePanel 弹窗共用 key） */
export class JtbdStore {
  static async read(ctx: Context): Promise<Record<string, Object>> {
    try {
      const p = await preferences.getPreferences(ctx, 'jtbd_store')
      const raw = p.getSync('jtbd_state', '') as string
      if (raw !== null && raw.length > 0) {
        return JSON.parse(raw) as Record<string, Object>
      }
    } catch (e) {
      console.warn('[P35] jtbd_store read fail: ' + e)
    }
    const empty: Record<string, Object> = {}
    return empty
  }

  static async write(ctx: Context, patch: Record<string, Object>): Promise<void> {
    try {
      const p = await preferences.getPreferences(ctx, 'jtbd_store')
      const cur = await JtbdStore.read(ctx)
      const merged: Record<string, Object> = {}
      for (const k of Object.keys(cur)) {
        merged[k] = cur[k]
      }
      for (const k of Object.keys(patch)) {
        merged[k] = patch[k]
      }
      await p.put('jtbd_state', JSON.stringify(merged))
      await p.flush()
      console.info('[P35] jtbd_store saved keys=' + Object.keys(patch).join(','))
    } catch (e) {
      console.warn('[P35] jtbd_store write fail: ' + e)
    }
  }
}

@Entry
@Component
struct JtbdSurveyPage {
  @StorageProp('darkMode') darkMode: boolean = false
  /** idle=Welcome / active=问答 / done=完成卡 */
  @State phase: string = 'idle'
  @State messages: SurveyMessage[] = []
  @State inputText: string = ''
  /** 已答问题数 0..3 */
  @State qIndex: number = 0
  @State answers: string[] = []

  private readonly QUESTIONS: string[] = [
    '你主要用 BrowserOS 做什么？',
    '你最想要什么改进？',
    '你愿意把 BrowserOS 推荐给朋友吗？'
  ]

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  private scroller: Scroller = new Scroller()

  private startSurvey(): void {
    this.phase = 'active'
    this.messages = [new SurveyMessage('agent', this.QUESTIONS[0])]
    console.info('[P35] survey started')
  }

  private sendAnswer(): void {
    const text = this.inputText.trim()
    if (text.length === 0) {
      return
    }
    this.messages.push(new SurveyMessage('user', text))
    this.answers.push(text)
    this.inputText = ''
    const next = this.qIndex + 1
    this.qIndex = next
    if (next < this.QUESTIONS.length) {
      this.messages.push(new SurveyMessage('agent', this.QUESTIONS[next]))
      console.info('[P35] survey Q' + (next + 1) + ' posed')
    } else {
      this.phase = 'done'
      this.persistAnswers()
    }
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 50)
  }

  private persistAnswers(): void {
    const ctx = getContext(this)
    const answersJson = JSON.stringify(this.answers)
    const patch: Record<string, Object> = {
      'surveyTaken': true,
      'answers': answersJson,
      'answeredAt': Date.now()
    }
    JtbdStore.write(ctx, patch).then(() => {
      console.info('[P35] survey answers persisted: ' + this.answers.length + ' items')
    })
  }

  private backToBrowser(): void {
    router.back()
  }

  build(): void {
    Column() {
      // 顶栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(18).height(18)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(30)
          .onClick(() => {
            router.back()
          })
        Text('BrowserOS 调查')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .margin({ left: 6 })
        Blank()
        if (this.phase === 'active') {
          Text(`${Math.min(this.qIndex + 1, this.QUESTIONS.length)}/${this.QUESTIONS.length}`)
            .fontSize(11)
            .fontColor(this.pal().text2)
        }
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 14 })
      .backgroundColor(this.pal().surfaceAlt)
      .border({ width: { bottom: 1 }, color: this.pal().border })

      Scroll() {
        Column() {
          if (this.phase === 'idle') {
            // Welcome 卡（对标上游 Welcome：橙圆 Sparkles + 标题 + 副标题 + Start Survey）
            Column() {
              Column() {
                Image($r('app.media.ic_sparkles'))
                  .width(30).height(30)
                  .fillColor('#F0983F')
                  .draggable(false)
              }
              .width(64)
              .height(64)
              .borderRadius(32)
              .backgroundColor('#1AF0983F')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ top: 30 })

              Text('Share Your Experience')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal().text)
                .margin({ top: 16 })
              Text("We'd love to learn about how you use browser automation. This quick conversation helps us build features that matter to you.")
                .fontSize(12)
                .fontColor(this.pal().text2)
                .textAlign(TextAlign.Center)
                .lineHeight(19)
                .margin({ top: 8, left: 24, right: 24 })

              Button('Start Survey')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .height(44)
                .padding({ left: 32, right: 32 })
                .backgroundColor('#F0983F')
                .fontColor('#FFFFFF')
                .borderRadius(22)
                .margin({ top: 24, bottom: 30 })
                .onClick(() => {
                  this.startSurvey()
                })
            }
            .width('94%')
            .borderRadius(14)
            .backgroundColor(this.pal().surface)
            .border({ width: 1, color: this.pal().border })
            .alignItems(HorizontalAlign.Center)
            .margin({ top: 40 })
          } else if (this.phase === 'active') {
            // 对话式问答（对标上游 Chat：气泡列表 + 输入 + 发送）
            Column() {
              List({ scroller: this.scroller }) {
                ForEach(this.messages, (msg: SurveyMessage, index: number) => {
                  ListItem() {
                    if (msg.role === 'user') {
                      Row() {
                        Blank()
                        Text(msg.text)
                          .fontSize(13)
                          .fontColor('#FFFFFF')
                          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                          .borderRadius(14)
                          .backgroundColor('#F0983F')
                          .constraintSize({ maxWidth: 250 })
                      }
                      .width('100%')
                    } else {
                      Row() {
                        Text(msg.text)
                          .fontSize(13)
                          .fontColor(this.pal().text)
                          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                          .borderRadius(14)
                          .backgroundColor(this.pal().surfaceAlt)
                          .constraintSize({ maxWidth: 250 })
                      }
                      .width('100%')
                    }
                  }
                  .padding({ top: 4, bottom: 4 })
                }, (msg: SurveyMessage, index: number) => index + '_' + msg.text)
              }
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Off)
            }
            .width('94%')
            .height('82%')
            .borderRadius(14)
            .backgroundColor(this.pal().surface)
            .border({ width: 1, color: this.pal().border })
            .margin({ top: 14 })
          } else {
            // 完成卡（对标上游 ThankYou：绿圆 Check + 感谢 + 返回浏览器）
            Column() {
              Column() {
                Image($r('app.media.ic_check'))
                  .width(30).height(30)
                  .fillColor('#22C55E')
                  .draggable(false)
              }
              .width(64)
              .height(64)
              .borderRadius(32)
              .backgroundColor('#1A22C55E')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ top: 30 })

              Text('Thank You!')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal().text)
                .margin({ top: 16 })
              Text('Your feedback helps us build better products. We appreciate you taking the time to share your experience.')
                .fontSize(12)
                .fontColor(this.pal().text2)
                .textAlign(TextAlign.Center)
                .lineHeight(19)
                .margin({ top: 8, left: 24, right: 24 })

              Button('返回浏览器')
                .fontSize(14)
                .height(40)
                .padding({ left: 26, right: 26 })
                .backgroundColor(this.pal().surfaceAlt)
                .fontColor(this.pal().text)
                .borderRadius(20)
                .border({ width: 1, color: this.pal().border })
                .margin({ top: 24, bottom: 30 })
                .onClick(() => {
                  this.backToBrowser()
                })
            }
            .width('94%')
            .borderRadius(14)
            .backgroundColor(this.pal().surface)
            .border({ width: 1, color: this.pal().border })
            .alignItems(HorizontalAlign.Center)
            .margin({ top: 40 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(this.pal().surfaceAlt)
      .align(Alignment.Top)

      // 底部输入区（仅 active 阶段）
      if (this.phase === 'active') {
        Row() {
          TextInput({ text: this.inputText, placeholder: '输入你的回答…' })
            .fontSize(13)
            .layoutWeight(1)
            .height(40)
            .backgroundColor(this.pal().surfaceAlt)
            .borderRadius(20)
            .onChange((v: string) => {
              this.inputText = v
            })
            .onSubmit(() => {
              this.sendAnswer()
            })
          Button('发送')
            .fontSize(13)
            .height(36)
            .backgroundColor('#F0983F')
            .fontColor('#FFFFFF')
            .borderRadius(18)
            .padding({ left: 18, right: 18 })
            .margin({ left: 8 })
            .enabled(this.inputText.trim().length > 0)
            .onClick(() => {
              this.sendAnswer()
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 10 })
        .backgroundColor(this.pal().surface)
        .border({ width: { top: 1 }, color: this.pal().border })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surfaceAlt)
  }
}
