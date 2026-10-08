import { Constants } from '../common/Constants'

@Component
export struct AddressBar {
  @State urlInput: string = ''
  @State currentUrl: string = ''
  @State isLoading: boolean = false
  onNavigate?: (url: string) => void
  onBack?: () => void
  onForward?: () => void
  onRefresh?: () => void
  onHome?: () => void

  build(): void {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_back'))
          .width(18).height(18)
          .fillColor('#5F6368')
          .draggable(false)
      }
      .width(36)
      .height(36)
      .onClick(() => {
        if (this.onBack) {
          this.onBack()
        }
      })

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_forward'))
          .width(18).height(18)
          .fillColor('#5F6368')
          .draggable(false)
      }
      .width(36)
      .height(36)
      .onClick(() => {
        if (this.onForward) {
          this.onForward()
        }
      })

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_reload'))
          .width(18).height(18)
          .fillColor('#5F6368')
          .draggable(false)
      }
      .width(36)
      .height(36)
      .onClick(() => {
        if (this.onRefresh) {
          this.onRefresh()
        }
      })

      Stack() {
        TextInput({ text: this.urlInput, placeholder: '输入URL或搜索关键词' })
          .layoutWeight(1)
          .height(36)
          .type(InputType.Normal)
          .onChange((value: string) => {
            this.urlInput = value
          })
          .onSubmit(() => {
            const input = this.urlInput
            if (this.isUrl(input)) {
              if (this.onNavigate) {
                this.onNavigate(input)
              }
            } else {
              if (this.onNavigate) {
                this.onNavigate(Constants.DEFAULT_SEARCH_ENGINE + encodeURIComponent(input))
              }
            }
          })

        if (this.isLoading) {
          LoadingProgress()
            .width(20)
            .height(20)
            .position({ x: '90%', y: 8 })
        }
      }
      .layoutWeight(1)

      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_home'))
            .width(20).height(20)
            .fillColor('#5F6368')
            .draggable(false)
          .fontSize(18)
          .fontColor('#666666')
      }
      .width(36)
      .height(36)
      .onClick(() => {
        if (this.onHome) {
          this.onHome()
        }
      })
    }
    .width('100%')
    .height(48)
    .padding({ left: 8, right: 8 })
    .backgroundColor('#F5F5F5')
  }

  private isUrl(input: string): boolean {
    return /^(https?:\/\/)?([\w-]+\.)+[\w-]+(\/[\w-./?%&=]*)?$/.test(input)
  }
}