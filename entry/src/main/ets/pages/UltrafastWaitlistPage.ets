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
import { I18n } from '../common/I18n'

@Entry
@Component
struct UltrafastWaitlistPage {
  // P49: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44
  @State emailInput: string = ''
  @State invalid: boolean = false
  @State joined: boolean = false
  @State joinedEmail: string = ''

  private readonly PERKS: string[] = [
    I18n.t('wlPerk1'),
    I18n.t('wlPerk2'),
    I18n.t('wlPerk3')
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

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('UltrafastWaitlistPage theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Column() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }

      Scroll() {
        Column() {
          // header（Coming soon + Ultrafast mode 大标 + 副题）
          Column() {
            Text(I18n.t('wlComingSoon'))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
              .letterSpacing(1.5)
            Text() {
              Span(I18n.t('wlUltrafast'))
                .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
                .fontWeight(FontWeight.Bold)
                .fontStyle(FontStyle.Italic)
              Span(I18n.t('wlMode'))
                .fontColor(this.pal().text)
                .fontWeight(FontWeight.Bold)
            }
            .fontSize(30)
            .margin({ top: 8 })
            Text(I18n.t('wlSubtitle'))
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

              Text(I18n.t('wlUnlimited'))
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
                  Span(I18n.t('wlMo'))
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
                Text(I18n.t('wlJoined'))
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
                  TextInput({ text: this.emailInput, placeholder: I18n.t('wlEmailPh') })
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
                  Button(I18n.t('wlJoin'))
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
                  Text(I18n.t('wlInvalidEmail'))
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
