@Entry
@Component
struct TestPage {
  build(): void {
    Column() {
      Text('BrowserOS Test Page')
        .fontSize(32)
        .fontColor('#333333')
        .margin({ top: 100 })

      Text('If you see this, the app window is working')
        .fontSize(16)
        .fontColor('#666666')
        .margin({ top: 20 })

      Button('Click Me')
        .fontSize(18)
        .backgroundColor('#007DFF')
        .fontColor('#FFFFFF')
        .margin({ top: 40 })
        .onClick(() => {
          console.info('Test button clicked')
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}