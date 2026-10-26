/**
 * P16a: 下载页 —— DownloadManager 真数据
 * 进行中(文件名+进度条+大小+取消) / 已完成(文件名+大小+时间+复制路径) / 失败(重试)
 */
import { router } from '@kit.ArkUI'
import { I18n } from '../common/I18n'
import { Palette } from '../common/Palette'
import { DownloadManager, DownloadItem, DownloadStatus } from '../service/DownloadManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { pasteboard } from '@kit.BasicServicesKit'

@Entry
@Component
struct DownloadsPage {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44
  @State items: DownloadItem[] = []
  @State copiedId: string = ''

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  aboutToAppear(): void {
    this.reload()
    EventBus.on(EventBusEvents.DOWNLOAD_CHANGED, this.onDlChanged)
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.DOWNLOAD_CHANGED, this.onDlChanged)
  }

  private onDlChanged = (data: Object): void => {
    this.items = DownloadManager.getDownloads().slice()
  }

  private reload(): void {
    this.items = DownloadManager.getDownloads().slice()
    console.info('DownloadsPage loaded: ' + this.items.length + ' items')
  }

  private fmtBytes(n: number): string {
    if (n <= 0) {
      return '0 B'
    }
    if (n < 1024) {
      return n + ' B'
    }
    if (n < 1024 * 1024) {
      return (n / 1024).toFixed(1) + ' KB'
    }
    if (n < 1024 * 1024 * 1024) {
      return (n / 1024 / 1024).toFixed(1) + ' MB'
    }
    return (n / 1024 / 1024 / 1024).toFixed(2) + ' GB'
  }

  private fmtTime(ts: number): string {
    if (!ts) {
      return ''
    }
    const d = new Date(ts)
    const p = (v: number): string => v < 10 ? '0' + v : '' + v
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
  }

  private copyPath(item: DownloadItem): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, item.filePath)
    pasteboard.getSystemPasteboard().setData(pasteData)
    this.copiedId = item.id
    console.info('DownloadsPage copy path: ' + item.filePath)
    setTimeout(() => {
      if (this.copiedId === item.id) {
        this.copiedId = ''
      }
    }, 1500)
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('DownloadsPage theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Column() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }

      Row() {
        Image($rawfile('ic_back.svg'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
          .onClick(() => {
            router.back()
          })
        Text(I18n.t('dlTitle'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text(this.items.length + I18n.t('dlItem'))
          .fontSize(11)
          .fontColor(this.pal().text2)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.pal().surfaceAlt)

      if (this.items.length === 0) {
        Column() {
          Image($rawfile('ic_download.svg'))
            .width(40).height(40)
            .fillColor(this.pal().text2)
            .draggable(false)
          Text(I18n.t('dlEmpty'))
            .fontSize(14)
            .fontColor(this.pal().text2)
            .margin({ top: 10 })
          Text(I18n.t('dlEmptyDesc'))
            .fontSize(11)
            .fontColor(this.pal().text2)
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            ForEach(this.items, (item: DownloadItem) => {
              this.DownloadRow(item)
            }, (item: DownloadItem) => item.id + '_' + item.status + '_' + item.receivedBytes)
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 16 })
        }
        .align(Alignment.Top)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surface)
  }

  @Builder
  DownloadRow(item: DownloadItem): void {
    Column() {
      Row() {
        Image($rawfile('ic_download.svg'))
          .width(18).height(18)
          .fillColor(item.status === DownloadStatus.FAILED ? '#D93025' : this.pal().accent)
          .draggable(false)
        Text(item.fileName)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })

        if (item.status === DownloadStatus.RUNNING) {
          Text(this.fmtBytes(item.totalBytes > 0 ? item.totalBytes : item.receivedBytes))
            .fontSize(11)
            .fontColor(this.pal().text2)
          Button({ type: ButtonType.Normal }) {
            Image($rawfile('ic_close.svg'))
              .width(14).height(14)
              .fillColor(this.pal().text2)
              .draggable(false)
          }
          .width(28).height(28)
          .backgroundColor(Color.Transparent)
          .margin({ left: 4 })
          .onClick(() => {
            console.info('DownloadsPage cancel: ' + item.id)
            DownloadManager.cancel(item.id)
          })
        } else if (item.status === DownloadStatus.FAILED) {
          Button(I18n.t('retry'))
            .fontSize(12)
            .height(28)
            .backgroundColor(this.pal().accent)
            .onClick(() => {
              console.info('DownloadsPage retry: ' + item.id)
              DownloadManager.retry(item.id)
            })
        } else if (item.status === DownloadStatus.COMPLETED) {
          Button(this.copiedId === item.id ? I18n.t('copied') : I18n.t('dlCopyPath'))
            .fontSize(12)
            .height(28)
            .backgroundColor(this.copiedId === item.id ? '#137333' : this.pal().accent)
            .onClick(() => {
              this.copyPath(item)
            })
        }
      }
      .width('100%')

      if (item.status === DownloadStatus.RUNNING) {
        // 进度条 + 已下载/总大小
        Progress({ value: item.totalBytes > 0 ? Math.floor(item.receivedBytes * 100 / item.totalBytes) : 0, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(this.pal().accent)
          .margin({ top: 6 })
        Text(item.totalBytes > 0
          ? `${this.fmtBytes(item.receivedBytes)} / ${this.fmtBytes(item.totalBytes)}`
          : this.fmtBytes(item.receivedBytes))
          .fontSize(10)
          .fontColor(this.pal().text2)
          .margin({ top: 3 })
      } else if (item.status === DownloadStatus.FAILED) {
        Text(I18n.t('dlFailed') + (item.error.length > 0 ? item.error : I18n.t('dlNetError')))
          .fontSize(10)
          .fontColor('#D93025')
          .margin({ top: 3 })
      } else if (item.status === DownloadStatus.COMPLETED) {
        Text(`${this.fmtBytes(item.receivedBytes)} · ${this.fmtTime(item.finishedAt)}`)
          .fontSize(10)
          .fontColor(this.pal().text2)
          .margin({ top: 3 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(8)
    .backgroundColor(this.pal().surfaceAlt)
    .margin({ top: 8 })
  }
}
