/**
 * P23b: LLM Hub 页 —— 供应商预设列表（增/删/设为当前）
 * 数据：AppConfig.llmProviders(JSON: [{name,baseUrl,apiKey,model}])
 * 「设为当前」= 写回 llmBaseUrl/llmApiKey/llmModel 三个生效字段（AgentEngine 零改动）
 */
import { ConfigManager } from '../storage/ConfigManager'
import { AppConfig, AppConfigUpdate } from '../model/AppConfig'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'

interface LlmProvider {
  name: string
  baseUrl: string
  apiKey: string
  model: string
}

@Entry
@Component
struct LlmHubPage {
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44
  @State providers: LlmProvider[] = []
  @State curBaseUrl: string = ''
  @State showAdd: boolean = false
  @State editIndex: number = -1
  // 表单
  @State fName: string = ''
  @State fUrl: string = ''
  @State fKey: string = ''
  @State fModel: string = ''
  @State formError: string = ''
  @State toast: string = ''

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  aboutToAppear(): void {
    this.reload()
  }

  private parseProviders(): LlmProvider[] {
    const raw = ConfigManager.get().llmProviders
    if (raw === null || raw === undefined || raw.length === 0) {
      return []
    }
    try {
      const arr = JSON.parse(raw) as LlmProvider[]
      if (Array.isArray(arr)) {
        return arr
      }
      return []
    } catch (e) {
      console.error('LlmHubPage parse providers error: ' + e)
      return []
    }
  }

  private reload(): void {
    this.providers = this.parseProviders()
    this.curBaseUrl = ConfigManager.get().llmBaseUrl
  }

  private async persist(list: LlmProvider[]): Promise<void> {
    const json = JSON.stringify(list)
    await ConfigManager.update({ llmProviders: json } as AppConfigUpdate)
    this.providers = list
  }

  private showToast(msg: string): void {
    this.toast = msg
    setTimeout(() => {
      this.toast = ''
    }, 1800)
  }

  private isCurrent(p: LlmProvider): boolean {
    return p.baseUrl === this.curBaseUrl && p.baseUrl.length > 0
  }

  private async applyProvider(p: LlmProvider): Promise<void> {
    const ok = await ConfigManager.update({
      llmBaseUrl: p.baseUrl,
      llmApiKey: p.apiKey,
      llmModel: p.model
    } as AppConfigUpdate)
    if (ok) {
      this.curBaseUrl = ConfigManager.get().llmBaseUrl
      this.showToast('已切换到 ' + p.name)
      console.info('LlmHub apply provider: ' + p.name + ' -> ' + p.baseUrl)
    } else {
      this.showToast('保存失败：端点格式不合法')
    }
  }

  private openAdd(): void {
    this.editIndex = -1
    this.fName = ''
    this.fUrl = ''
    this.fKey = ''
    this.fModel = ''
    this.formError = ''
    this.showAdd = true
  }

  private openEdit(i: number): void {
    const p = this.providers[i]
    this.editIndex = i
    this.fName = p.name
    this.fUrl = p.baseUrl
    this.fKey = p.apiKey
    this.fModel = p.model
    this.formError = ''
    this.showAdd = true
  }

  private async saveForm(): Promise<void> {
    const name = this.fName.trim()
    const url = AppConfig.sanitizeLlmBaseUrl(this.fUrl)
    const key = this.fKey.trim()
    const model = this.fModel.trim()
    if (name.length === 0) {
      this.formError = '名称不能为空'
      return
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.formError = '端点必须以 http:// 或 https:// 开头'
      return
    }
    const list = this.parseProviders()
    const item: LlmProvider = { name: name, baseUrl: url, apiKey: key, model: model }
    if (this.editIndex >= 0 && this.editIndex < list.length) {
      list[this.editIndex] = item
    } else {
      list.push(item)
    }
    await this.persist(list)
    this.showAdd = false
    this.showToast(this.editIndex >= 0 ? '已更新 ' + name : '已添加 ' + name)
  }

  private async removeAt(i: number): Promise<void> {
    const list = this.parseProviders()
    const removed = list.splice(i, 1)
    await this.persist(list)
    if (removed.length > 0) {
      this.showToast('已删除 ' + removed[0].name)
    }
  }

  private maskKey(k: string): string {
    if (k.length === 0) {
      return '(无 Key)'
    }
    if (k.length <= 8) {
      return '••••'
    }
    return k.substring(0, 4) + '••••' + k.substring(k.length - 4)
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('LlmHubPage theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Column() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }

      // 头部
      Row() {
        Image($rawfile('ic_back.svg'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
          .accessibilityText('返回')
          .onClick(() => {
            router.back()
          })
        Text('LLM Hub')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text('添加')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A73E8')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.pal().selected)
          .borderRadius(14)
          .onClick(() => {
            this.openAdd()
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.pal().surfaceAlt)

      // 当前生效提示
      Text('当前: ' + (this.curBaseUrl.length > 0 ? this.curBaseUrl : '(未配置)'))
        .fontSize(11)
        .fontColor(this.pal().text2)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 24, top: 10, bottom: 2 })

      // 添加/编辑面板
      if (this.showAdd) {
        Column() {
          Text(this.editIndex >= 0 ? '编辑供应商' : '添加供应商')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal().text)
            .alignSelf(ItemAlign.Start)

          this.FormField('名称', this.fName, '如：本地 Ollama', (v: string) => {
            this.fName = v
          })
          this.FormField('API 端点', this.fUrl, 'https://api.example.com/v1', (v: string) => {
            this.fUrl = v
          })
          this.FormField('API Key', this.fKey, 'sk-...（可留空）', (v: string) => {
            this.fKey = v
          })
          this.FormField('模型', this.fModel, '如：gpt-4o-mini', (v: string) => {
            this.fModel = v
          })

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
                this.showAdd = false
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
                this.saveForm()
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

      // 空态/列表
      if (this.providers.length === 0) {
        Column() {
          Text('暂无供应商预设')
            .fontSize(13)
            .fontColor(this.pal().text2)
            .margin({ top: 8 })
          Text('添加后可一键切换代理的模型后端')
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 4 })
        }
        .width('100%')
        .margin({ top: 100 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.providers, (p: LlmProvider, i: number) => {
              Column() {
                Row() {
                  Column() {
                    Row() {
                      Text(p.name)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.pal().text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (this.isCurrent(p)) {
                        Text('当前')
                          .fontSize(10)
                          .fontColor('#1A73E8')
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .backgroundColor(this.pal().selected)
                          .borderRadius(8)
                          .margin({ left: 6 })
                      }
                    }
                    Text(p.baseUrl + ' · ' + (p.model.length > 0 ? p.model : '默认模型') + ' · ' + this.maskKey(p.apiKey))
                      .fontSize(11)
                      .fontColor(this.pal().text2)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')

                Row() {
                  Blank()
                  if (!this.isCurrent(p)) {
                    Text('设为当前')
                      .fontSize(12)
                      .fontColor('#1A73E8')
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .onClick(() => {
                        this.applyProvider(p)
                      })
                  }
                  Text('编辑')
                    .fontSize(12)
                    .fontColor(this.pal().text2)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .onClick(() => {
                      this.openEdit(i)
                    })
                  Text('删除')
                    .fontSize(12)
                    .fontColor('#C5221F')
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .onClick(() => {
                      this.removeAt(i)
                    })
                }
                .width('100%')
                .margin({ top: 4 })

                Divider().color('#F1F3F4').margin({ top: 8 })
              }
              .padding({ top: 10, bottom: 4 })
            }, (p: LlmProvider) => p.name + '_' + p.baseUrl)
          }
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 30 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }

      // toast
      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor('#323639')
          .borderRadius(16)
          .margin({ bottom: 40 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surface)
  }

  @Builder
  FormField(label: string, value: string, hint: string, onChange: (v: string) => void) {
    Text(label)
      .fontSize(11)
      .fontColor(this.pal().text2)
      .margin({ top: 10, bottom: 4 })
      .alignSelf(ItemAlign.Start)
    TextInput({ text: value, placeholder: hint })
      .width('100%')
      .height(36)
      .fontSize(13)
      .fontColor(this.pal().text)
      .placeholderColor(this.pal().text2)
      .backgroundColor(this.pal().surfaceAlt)
      .borderRadius(8)
      .onChange((v: string) => {
        onChange(v)
      })
  }
}
