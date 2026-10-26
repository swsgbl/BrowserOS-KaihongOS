/**
 * P11c: 查看网页源码页(view-source 等价物)
 * 隐藏 1x1 Web 加载目标页 → onPageEnd 后 runJavaScript 取
 * document.documentElement.outerHTML → 只读等宽文本展示(截断 120k 字符)
 */
import { webview } from '@kit.ArkWeb'
import { I18n } from '../common/I18n'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'

@Entry
@Component
struct ViewSourcePage {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44
  @State srcUrl: string = ''
  @State source: string = ''
  @State ready: boolean = false
  @State failed: string = ''
  private controller: webview.WebviewController = new webview.WebviewController()

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>
    if (params && params['url']) {
      this.srcUrl = params['url'] as string
    }
    console.info('ViewSourcePage url=' + this.srcUrl)
  }

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('ViewSourcePage theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Stack() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }

      // 隐身加载器:1x1 + 透明,只为执行 JS 取 outerHTML
      Web({ src: this.srcUrl, controller: this.controller })
        .width(1)
        .height(1)
        .opacity(0)
        .onPageEnd(() => {
          console.info('ViewSourcePage loaded, fetching outerHTML')
          this.controller.runJavaScript('document.documentElement.outerHTML')
            .then((result: string) => {
              let html = result
              try {
                html = JSON.parse(result) as string
              } catch (e) {
                console.error('ViewSourcePage unescape fallback: ' + e)
              }
              this.source = html.length > 120000
                ? html.substring(0, 120000) + '\n<!-- P11: 超长截断 -->'
                : html
              this.ready = true
            })
            .catch((err: Object) => {
              console.error('ViewSourcePage runJavaScript error: ' + err)
              this.failed = I18n.t('vsFetchFail') + err
              this.ready = true
            })
        })
        .onErrorReceive((event) => {
          if (!this.ready) {
            this.failed = I18n.t('vsLoadFail') + (event.error ? event.error.getErrorInfo() : 'unknown')
            this.ready = true
          }
        })

      // 源码展示层
      Column() {
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($rawfile('ic_back.svg'))
              .width(18).height(18)
              .fillColor(this.pal().text2)
              .draggable(false)
          }
          .width(32).height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.back()
          })

          Text('view-source:' + this.srcUrl)
            .fontSize(12)
            .fontColor(this.pal().text2)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 4 })

          Text(I18n.t('close'))
            .fontSize(13)
            .fontColor('#1A73E8')
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              router.back()
            })
        }
        .width('100%')
        .height(44)
        .padding({ left: 8, right: 8 })
        .backgroundColor(this.pal().surfaceAlt)

        Divider().color(this.pal().border)

        if (!this.ready) {
          Column() {
            LoadingProgress().width(28).height(28)
            Text(I18n.t('vsLoading'))
              .fontSize(12)
              .fontColor(this.pal().text2)
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.failed.length > 0) {
          Column() {
            Text(this.failed)
              .fontSize(13)
              .fontColor('#C5221F')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Text(this.source)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor(this.pal().text)
              .textAlign(TextAlign.Start)
              .width('100%')
              .padding(8)
          }
          .align(Alignment.TopStart)
          .layoutWeight(1)
          .scrollBar(BarState.On)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().surface)
    }
    .width('100%')
    .height('100%')
  }
}
