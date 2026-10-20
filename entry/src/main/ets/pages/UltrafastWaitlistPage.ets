/**
 * P35-B: Ultrafast 等待页（对标上游 UltrafastWaitlist.tsx）
 * - 价格行：$5/mo 固定展示 + ⚡Zap 图标
 * - PERKS 3 条原文（Faster clicks... / Bring your own Claude... / Use 10× fewer tokens...）
 * - email 输入 + Join waitlist：正则校验 + normalize(trim+lowercase)，不过显红字
 * - 通过 → ultrafast_store(joined=true+email) + 已加入态（Check + You're on the list）
 * - 深浅色适配
 */
import { preferences } from '@kit.ArkData'
import { Palette } from '../common/Palette'

@Entry
@Component
struct UltrafastWaitlistPage {
  @StorageProp('darkMode') darkMode: boolean = false
  @State emailInput: string = ''
  @State invalid: boolean = false
  @State joined: boolean = false
  @State joinedEmail: string = ''

  private readonly PERKS: string[] = [
    'Faster clicks, typing, and navigation',
    'Bring your own Claude, Codex, or other agent subscription to power your main agent',
    'Use 10× fewer tokens from your main agent, with our browser-action model handling most actions'
  ]

  private readonly EMAIL_PATTERN: RegExp = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  aboutToAppear(): void {
    try {
      const ctx = getContext(this)
      preferences.getPreferences(ctx, 'ultrafast_store').then((p: preferences.Preferences) => {
        const j = p.getSync('ultrafast_joined', false) as boolean
        const e = p.getSync('ultrafast_email', '') as string
        this.joined = j
        this.joinedEmail = e
        console.info('[P35] ultrafast waitlist state: joined=' + j)
      }).catch((e: Object) => {
        console.warn('[P35] ultrafast prefs load fail: ' + e)
      })
    } catch (e) {
      console.warn('[P35] ultrafast getContext fail: ' + e)
    }
  }

  private submitJoin(): void {
    if (this.joined) {
      return
    }
    const email = this.emailInput.trim().toLowerCase()
    if (!this.EMAIL_PATTERN.test(email)) {
      this.invalid = true
      console.info('[P35] ultrafast invalid email: "' + this.emailInput + '"')
      return
    }
    this.invalid = false
    this.joined = true
    this.joinedEmail = email
    console.info('[P35] ultrafast joined: ' + email)
    try {
      const ctx = getContext(this)
      preferences.getPreferences(ctx, 'ultrafast_store').then((p: preferences.Preferences) => {
        p.put('ultrafast_joined', true).then(() => {
          return p.put('ultrafast_email', email)
        }).then(() => {
          return p.flush()
        }).then(() => {
          console.info('[P35] ultrafast joined persisted: ' + email)
        }).catch((e: Object) => {
          console.error('[P35] ultrafast join persist fail: ' + e)
        })
      })
    } catch (e) {
      console.error('[P35] ultrafast persist exception: ' + e)
    }
  }

  build(): void {
    Column() {
      Scroll() {
        Column() {
          // header（Coming soon + Ultrafast mode 大标 + 副题）
          Column() {
            Text('COMING SOON')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
              .letterSpacing(1.5)
            Text() {
              Span('Ultrafast')
                .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
                .fontWeight(FontWeight.Bold)
                .fontStyle(FontStyle.Italic)
              Span(' mode')
                .fontColor(this.pal().text)
                .fontWeight(FontWeight.Bold)
            }
            .fontSize(30)
            .margin({ top: 8 })
            Text('We trained our own browser-action model for faster browser tasks.')
              .fontSize(13)
              .fontColor(this.pal().text2)
              .margin({ top: 8 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 34, left: 26 })

          // 价格 + perks 卡
          Column() {
            Row() {
              Column() {
                Image($rawfile('ic_zap.svg'))
                  .width(22).height(22)
                  .fillColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
                  .draggable(false)
              }
              .width(40)
              .height(40)
              .borderRadius(10)
              .backgroundColor(this.darkMode ? '#337CB1FF' : '#1A73E81A')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Text('Unlimited browser-action model access')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal().text)
                .layoutWeight(1)
                .maxLines(2)
                .margin({ left: 12 })

              Column() {
                Text() {
                  Span('$5')
                    .fontSize(28)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.pal().text)
                  Span('/mo')
                    .fontSize(13)
                    .fontColor(this.pal().text2)
                }
                .baselineOffset(6)
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // PERKS 3 条
            Column() {
              ForEach(this.PERKS, (perk: string, index: number) => {
                Row() {
                  Image($rawfile('ic_check.svg'))
                    .width(17).height(17)
                    .fillColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
                    .draggable(false)
                    .margin({ top: 2 })
                  Text(perk)
                    .fontSize(13)
                    .fontColor(this.pal().text)
                    .lineHeight(20)
                    .layoutWeight(1)
                    .margin({ left: 10 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .margin({ top: index === 0 ? 0 : 12 })
              }, (perk: string, index: number) => 'perk_' + index)
            }
            .width('100%')
            .margin({ top: 20 })

            // email 表单 / 已加入态
            if (this.joined) {
              Row() {
                Image($rawfile('ic_check.svg'))
                  .width(15).height(15)
                  .fillColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
                  .draggable(false)
                Text(`You're on the list. We'll email you when it's ready.`)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.pal().text)
                  .margin({ left: 8 })
                  .layoutWeight(1)
              }
              .width('100%')
              .margin({ top: 20 })
              .alignItems(VerticalAlign.Center)
            } else {
              Column() {
                Row() {
                  TextInput({ text: this.emailInput, placeholder: 'you@example.com' })
                    .fontSize(13)
                    .layoutWeight(1)
                    .height(42)
                    .fontColor(this.pal().text)
                    .placeholderColor(this.pal().text2)
                    .backgroundColor(this.pal().surfaceAlt)
                    .borderRadius(8)
                    .border({ width: 1, color: this.invalid ? '#DC2626' : this.pal().border })
                    .onChange((v: string) => {
                      this.emailInput = v
                      this.invalid = false
                    })
                    .onSubmit(() => {
                      this.submitJoin()
                    })
                  Button('Join waitlist')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .height(42)
                    .padding({ left: 18, right: 18 })
                    .backgroundColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
                    .fontColor(this.darkMode ? '#0D1117' : '#FFFFFF')
                    .borderRadius(8)
                    .margin({ left: 10 })
                    .onClick(() => {
                      this.submitJoin()
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                if (this.invalid) {
                  Text('Enter a valid email address.')
                    .fontSize(12)
                    .fontColor('#DC2626')
                    .margin({ top: 8 })
                }
              }
              .width('100%')
              .margin({ top: 20 })
            }
          }
          .width('88%')
          .borderRadius(14)
          .backgroundColor(this.pal().surface)
          .border({ width: 1, color: this.pal().border })
          .padding(20)
          .margin({ top: 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surfaceAlt)
  }
}
