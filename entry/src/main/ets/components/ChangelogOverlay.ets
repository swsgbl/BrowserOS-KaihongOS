/**
 * P33-D: 更新日志弹层(对标上游 changelog 通知)
 * 组件自治版:aboutToAppear 里 bundleManager 版本 vs Preferences last_changelog_version,
 * 不同则 5s 后弹版本要点卡;「知道了」关闭并写回标记。不依赖 AppStorage 跨上下文同步
 * (EntryAbility 侧 setOrCreate 无法驱动页面 @StorageProp 刷新,实测 KaihongOS 上断链)。
 */
import { bundleManager } from '@kit.AbilityKit'
import { I18n } from '../common/I18n'
import { preferences } from '@kit.ArkData'
import { BusinessError } from '@kit.BasicServicesKit'

@Component
export struct ChangelogOverlay {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  @State visible: boolean = false
  @State version: string = ''
  /** 版本要点(本版写死:对标上游 CHANGELOG 内容条目) */
  private readonly bullets: string[] = [
    I18n.t('clLine1'),
    I18n.t('clLine2'),
    I18n.t('clLine3'),
    I18n.t('clLine4')
  ]

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      const version = info.versionName
      this.version = version
      console.info('[P33] overlay check: current=' + version)
      const ctx = getContext(this)
      preferences.getPreferences(ctx, 'app_state_prefs').then((p: preferences.Preferences) => {
        return p.get('last_changelog_version', '')
      }).then((v: preferences.ValueType) => {
        const last = `${v}`
        if (last !== version) {
          console.info('[P33] overlay pending: last=' + last + ' current=' + version + ' (dialog in 5s)')
          setTimeout(() => {
            this.visible = true
            console.info('[P33] overlay dialog shown for v' + version)
          }, 5000)
        } else {
          console.info('[P33] overlay already shown for v' + version)
        }
      }).catch((e: BusinessError) => {
        console.warn('[P33] overlay pref read error: ' + e.code)
      })
    } catch (e) {
      console.warn('[P33] overlay check exception: ' + e)
    }
  }

  private palColor(): string {
    const dark = AppStorage.get<boolean>('darkMode') === true
    return dark ? '#292A2D' : '#FFFFFF'
  }

  private textColor(): string {
    const dark = AppStorage.get<boolean>('darkMode') === true
    return dark ? '#E8EAED' : '#202124'
  }

  private lineColor(): string {
    const dark = AppStorage.get<boolean>('darkMode') === true
    return dark ? '#3C4043' : '#DADCE0'
  }

  build(): void {
    if (this.visible) {
      Stack() {
        // 遮罩(点击不关闭——须点「知道了」,防误触跳过)
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')

        // 弹层卡(Stack 默认居中,叠在遮罩上)
        Column() {
          Text(I18n.t('dlgUpdateTitle'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor())
            .margin({ top: 22 })
          Text('v' + this.version)
            .fontSize(11)
            .fontColor('#1A73E8')
            .margin({ top: 4 })

          Column() {
            ForEach(this.bullets, (b: string, idx: number) => {
              Row() {
                Text('·')
                  .fontSize(13)
                  .fontColor('#1A73E8')
                  .margin({ right: 8 })
                Text(b)
                  .fontSize(13)
                  .fontColor(this.textColor())
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .alignSelf(ItemAlign.Start)
                  .layoutWeight(1)
              }
              .alignItems(VerticalAlign.Top)
              .width('100%')
              .margin({ top: 10 })
            }, (b: string, idx: number) => 'cl_' + idx)
          }
          .width('100%')
          .constraintSize({ maxWidth: 300 })
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 22, right: 22 })

          Button(I18n.t('gotIt'))
            .fontSize(14)
            .height(38)
            .width(140)
            .backgroundColor('#1A73E8')
            .fontColor('#FFFFFF')
            .borderRadius(19)
            .margin({ top: 26, bottom: 22 })
            .onClick(() => {
              this.visible = false
              console.info('[P33] overlay dismissed')
              try {
                const ctx = getContext(this)
                preferences.getPreferences(ctx, 'app_state_prefs').then((p: preferences.Preferences) => {
                  p.put('last_changelog_version', this.version).then(() => {
                    return p.flush()
                  }).then(() => {
                    console.info('[P33] overlay marked shown for v' + this.version)
                  }).catch((e: BusinessError) => {
                    console.warn('[P33] overlay mark error: ' + e.code)
                  })
                })
              } catch (e) {
                console.warn('[P33] overlay mark exception: ' + e)
              }
            })
        }
        .width('86%')
        .constraintSize({ maxWidth: 340 })
        .borderRadius(16)
        .backgroundColor(this.palColor())
        .border({ width: 1, color: this.lineColor() })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }
}
