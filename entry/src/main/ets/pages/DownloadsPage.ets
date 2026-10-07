/**
 * P9-C4: 下载页 —— 如实空态（无真实下载管理器）+ 列表结构说明
 */
import { router } from '@kit.ArkUI'

@Entry
@Component
struct DownloadsPage {
  build(): void {
    Column() {
      Row() {
        Text('←')
          .fontSize(18)
          .fontColor('#5F6368')
          .width(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back()
          })
        Text('下载内容')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#202124')
          .layoutWeight(1)
        Text('0 项')
          .fontSize(11)
          .fontColor('#5F6368')
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 16 })
      .backgroundColor('#F1F3F4')

      Column() {
        Text('⭳')
          .fontSize(40)
          .fontColor('#DADCE0')
        Text('暂无下载内容')
          .fontSize(14)
          .fontColor('#5F6368')
          .margin({ top: 10 })
        Text('当前版本未内置下载管理器；文件下载将由系统接管。\n列表结构（文件名 / 来源 / 时间 / 打开）已就绪，接入下载事件源即可展示。')
          .fontSize(11)
          .fontColor('#9AA0A6')
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
