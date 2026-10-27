/**
 * P53: Chrome 登录态导入向导 —— 四步流程
 * Step1 选择来源 → Step2 选择文件 → Step3 预览勾选 → Step4 执行+结果
 *
 * 平台事实：KaihongOS 应用沙盒无法直读其他应用 profile，必须走文件导入
 * （DocumentViewPicker，同 P32 书签导入先例）。
 * 支持格式：Netscape cookie.txt / Chrome Cookie JSON / Bitwarden JSON / 手动输入
 */
import { router } from '@kit.ArkUI'
import { picker } from '@kit.CoreFileKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import {
  LoginStateManager,
  ImportSourceKind,
  ImportPreviewRow,
  ImportSummary,
  ImportDomainResult,
  LoginStateData,
  CookieEntry
} from '../service/LoginStateManager'
import { I18n } from '../common/I18n'

/** 来源卡片定义 */
class SourceCard {
  kind: ImportSourceKind = ImportSourceKind.NETSCAPE
  title: string = ''
  desc: string = ''
  fields: string = ''
}

@Entry
@Component
struct ImportWizardPage {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false
  @State themeVersion: number = 0

  onThemeFlip(): void {
    this.themeVersion++
  }

  // 向导状态机
  @State step: number = 1
  @State sourceKind: ImportSourceKind = ImportSourceKind.NETSCAPE
  @State pickedFileName: string = ''
  @State parsedStates: LoginStateData[] = []
  @State previewRows: ImportPreviewRow[] = []
  @State selectedDomains: Set<string> = new Set()
  @State parseError: string = ''
  @State importing: boolean = false
  @State summary: ImportSummary | null = null
  // 手动输入
  @State manualDomain: string = ''
  @State manualCookieName: string = ''
  @State manualCookieValue: string = ''

  private fileUri: string = ''
  private fileText: string = ''
  @State sandboxPath: string = ''   // P53: filesDir 相对路径直读（picker 兜底）
  @State sandboxFiles: string[] = []   // P53: 沙盒可导入文件扫描结果

  private bg(): string {
    return this.darkMode ? '#161B22' : '#FFFFFF'
  }
  private card(): string {
    return this.darkMode ? '#1E242C' : '#F6F8FA'
  }
  private text(): string {
    return this.darkMode ? '#E6EDF3' : '#1F2328'
  }
  private text2(): string {
    return this.darkMode ? '#8B949E' : '#57606A'
  }
  private brd(): string {
    return this.darkMode ? '#30363D' : '#D0D7DE'
  }
  private accent(): string {
    return '#1A73E8'
  }
  private warn(): string {
    return '#D29922'
  }
  private ok(): string {
    return '#3FB950'
  }

  private sourceCards(): SourceCard[] {
    const cards: SourceCard[] = []
    let c = new SourceCard()
    c.kind = ImportSourceKind.NETSCAPE
    c.title = 'Chrome Cookie 导出 (Netscape cookie.txt)'
    c.desc = '浏览器扩展（如 Get cookies.txt）导出的标准格式'
    c.fields = 'domain / path / secure / expiry / name / value'
    cards.push(c)
    c = new SourceCard()
    c.kind = ImportSourceKind.CHROME_JSON
    c.title = 'Chrome Cookie JSON'
    c.desc = 'EditThisCookie 等扩展导出的 {"cookies":[...]} 格式'
    c.fields = 'domain / name / value / path / expires / secure / httpOnly'
    cards.push(c)
    c = new SourceCard()
    c.kind = ImportSourceKind.BITWARDEN
    c.title = 'Bitwarden JSON'
    c.desc = 'Bitwarden 导出的 {"encrypted":false,"items":[...]} 未加密 json'
    c.fields = 'uri / username / password（凭据存入凭据库语义）'
    cards.push(c)
    c = new SourceCard()
    c.kind = ImportSourceKind.MANUAL
    c.title = '手动输入'
    c.desc = '手工录入单个域名的 cookie'
    c.fields = 'domain / name / value'
    cards.push(c)
    return cards
  }

  private sourceLabel(k: ImportSourceKind): string {
    if (k === ImportSourceKind.NETSCAPE) {
      return 'Netscape cookie.txt'
    }
    if (k === ImportSourceKind.CHROME_JSON) {
      return 'Chrome Cookie JSON'
    }
    if (k === ImportSourceKind.BITWARDEN) {
      return 'Bitwarden JSON'
    }
    return '手动输入'
  }

  // ---------- Step2: 文件选择（P32 先例 DocumentViewPicker） ----------
  private pickFile(): void {
    const hostCtx = this.getUIContext().getHostContext()
    const docPicker = hostCtx !== undefined ? new picker.DocumentViewPicker(hostCtx) : new picker.DocumentViewPicker()
    const opts = new picker.DocumentSelectOptions()
    opts.fileSuffixFilters = ['txt', 'json']
    opts.maxSelectNumber = 1
    docPicker.select(opts).then((uris: Array<string>) => {
      if (uris.length === 0) {
        return
      }
      this.onFilePicked(uris[0])
    }).catch((e: Object) => {
      console.info('ImportWizard picker dismissed: ' + e)
    })
  }

  private onFilePicked(uri: string): void {
    this.fileUri = uri
    this.parseError = ''
    try {
      let file: fs.File | null = fs.openSync(uri, fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      file = null
      this.fileText = util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer))
    } catch (e) {
      this.parseError = `读取文件失败: ${e}`
      return
    }
    // 文件名展示（uri 末段）
    const segs = uri.split('/')
    this.pickedFileName = segs.length > 0 ? segs[segs.length - 1] : uri
    this.parseAndPreview()
  }

  // ---------- 解析 + 预览 ----------
  private parseAndPreview(): void {
    const states = LoginStateManager.parseAny(this.fileText, this.sourceKind)
    if (states.length === 0) {
      this.parseError = '未能解析出任何登录态（格式不识别或内容为空）'
      this.parsedStates = []
      this.previewRows = []
      return
    }
    this.parsedStates = states
    this.previewRows = LoginStateManager.buildPreview(states)
    const sel = new Set<string>()
    for (const row of this.previewRows) {
      sel.add(row.domain)
    }
    this.selectedDomains = sel
    this.step = 3
  }

  // ---------- P53: 扫描沙盒可导入文件（.txt/.json） ----------
  private scanSandbox(): void {
    const names = LoginStateManager.listSandboxImportable()
    this.sandboxFiles = names
    console.info('[P53] scanSandbox: found ' + names.length + ' files: ' + names.join(','))
  }

  // ---------- P53: 沙盒路径直读 ----------
  private loadFromSandbox(): void {
    const rel = this.sandboxPath.trim().replace(/^files\//, '')
    this.parseError = ''
    const text = LoginStateManager.readSandboxText(rel)
    if (text.length === 0) {
      this.parseError = `沙盒文件读取失败或为空: files/${rel}`
      return
    }
    this.fileText = text
    this.pickedFileName = 'files/' + rel
    this.parseAndPreview()
  }

  // ---------- 手动输入构造单域 state ----------
  private manualBuild(): void {
    const domain = this.manualDomain.trim()
    const name = this.manualCookieName.trim()
    if (domain.length === 0 || name.length === 0) {
      this.parseError = '域名与 Cookie 名必填'
      return
    }
    this.parseError = ''
    const state = new LoginStateData(domain.replace(/^\./, ''))
    const entry = new CookieEntry(name, this.manualCookieValue, state.domain)
    state.addCookie(entry)
    this.parsedStates = [state]
    this.previewRows = LoginStateManager.buildPreview(this.parsedStates)
    const sel = new Set<string>()
    sel.add(state.domain)
    this.selectedDomains = sel
    this.step = 3
  }

  // ---------- Step4: 执行 ----------
  private async doImport(): Promise<void> {
    this.importing = true
    this.summary = null
    const domains: string[] = []
    this.selectedDomains.forEach((d: string) => {
      domains.push(d)
    })
    const summary = await LoginStateManager.executeImport(this.parsedStates, domains)
    this.summary = summary
    this.importing = false
  }

  private fmtExpiry(ts: number): string {
    if (ts <= 0) {
      return '会话'
    }
    const d = new Date(ts * 1000)
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n)
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  }

  private toggleDomain(domain: string): void {
    const next = new Set<string>()
    this.selectedDomains.forEach((d: string) => {
      next.add(d)
    })
    if (next.has(domain)) {
      next.delete(domain)
    } else {
      next.add(domain)
    }
    this.selectedDomains = next
  }

  build(): void {
    Stack() {
      Column() {
        if (this.themeVersion < 0 || this.localeVersion < 0) {
          Text('').fontSize(0)
        }
        // 顶栏
        Row() {
          Button({ type: ButtonType.Normal }) {
            Text(this.step > 1 && this.step < 4 ? '←' : '✕')
              .fontSize(18).fontColor(this.text2())
          }
          .width(40).height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.step === 2 || this.step === 3) {
              this.step = this.step - 1
            } else {
              router.back()
            }
          })
          Column() {
            Text('登录态导入向导')
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.text())
            Text(`步骤 ${this.step} / 4`)
              .fontSize(12).fontColor(this.text2())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })

        // 步骤指示条
        Row() {
          ForEach([1, 2, 3, 4], (s: number) => {
            Row() {
              Circle({ width: 22, height: 22 })
                .fill(s <= this.step ? this.accent() : this.brd())
                .margin({ right: 6 })
              Text(this.stepNames(s))
                .fontSize(12)
                .fontColor(s <= this.step ? this.accent() : this.text2())
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          })
        }
        .width('100%')
        .padding(8)

        Divider().color(this.brd())

        // 主体
        Scroll() {
          Column() {
            if (this.step === 1) {
              this.StepSource()
            } else if (this.step === 2) {
              this.StepFile()
            } else if (this.step === 3) {
              this.StepPreview()
            } else {
              this.StepResult()
            }
          }
          .width('100%')
          .padding(16)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // 底部动作条
        if (this.step < 4) {
          Row() {
            Button(this.step === 3 ? '执行导入' : '下一步')
              .fontSize(16).fontColor(Color.White)
              .backgroundColor(this.accent())
              .borderRadius(20)
              .height(44)
              .layoutWeight(1)
              .enabled(this.canNext())
              .opacity(this.canNext() ? 1.0 : 0.4)
              .onClick(() => {
                if (this.step === 1) {
                  this.step = 2
                } else if (this.step === 2) {
                  if (this.sandboxPath.trim().length > 0) {
                    this.loadFromSandbox()
                  } else if (this.sourceKind === ImportSourceKind.MANUAL) {
                    this.manualBuild()
                  } else {
                    this.pickFile()
                  }
                } else if (this.step === 3) {
                  this.step = 4
                  this.doImport()
                }
              })
          }
          .width('100%')
          .padding(12)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bg())
    }
  }

  private stepNames(s: number): string {
    if (s === 1) {
      return '选择来源'
    }
    if (s === 2) {
      return '选择文件'
    }
    if (s === 3) {
      return '预览'
    }
    return '执行'
  }

  private canNext(): boolean {
    if (this.step === 1) {
      return true
    }
    if (this.step === 2) {
      return true // 文件选择在按钮触发时进行
    }
    if (this.step === 3) {
      return this.selectedDomains.size > 0
    }
    return false
  }

  // ---------- Step1 UI ----------
  @Builder
  StepSource() {
    Column() {
      Text('选择导入来源')
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.text())
        .margin({ bottom: 12 })
      Text('KaihongOS 应用沙盒无法直接读取 Chrome 的 profile 数据，请先在电脑端用浏览器扩展导出 Cookie 文件，再导入到本浏览器。')
        .fontSize(13).fontColor(this.text2())
        .margin({ bottom: 16 })
        .lineHeight(20)
      ForEach(this.sourceCards(), (card: SourceCard) => {
        Row() {
          Radio({ value: card.title, group: 'src' })
            .checked(this.sourceKind === card.kind)
            .onChange((on: boolean) => {
              if (on) {
                this.sourceKind = card.kind
              }
            })
            .margin({ right: 10 })
          Column() {
            Text(card.title)
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.text())
            Text(card.desc)
              .fontSize(12).fontColor(this.text2())
              .margin({ top: 2 })
            Text(`字段: ${card.fields}`)
              .fontSize(11).fontColor(this.text2())
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor(this.card())
        .border({ width: 1, color: this.sourceKind === card.kind ? this.accent() : this.brd() })
        .margin({ bottom: 10 })
        .onClick(() => {
          this.sourceKind = card.kind
        })
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---------- Step2 UI ----------
  @Builder
  StepFile() {
    Column() {
      Text(`来源: ${this.sourceLabel(this.sourceKind)}`)
        .fontSize(14).fontColor(this.accent())
        .margin({ bottom: 12 })
      // P53: 沙盒路径直读（无 picker 环境的兜底：adb 预置 files/ 后填相对路径）
      Text('或直接填写应用沙盒内路径 (files/ 下相对路径)')
        .fontSize(13).fontColor(this.text2())
        .margin({ top: 16, bottom: 6 })
      TextInput({ placeholder: 'cookies.txt' })
        .fontSize(14)
        .onChange((v: string) => { this.sandboxPath = v })
        .margin({ bottom: 6 })
      Button('扫描沙盒可导入文件')
        .fontSize(13).fontColor(this.accent())
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: this.accent() })
        .borderRadius(14)
        .height(30)
        .margin({ bottom: 6 })
        .onClick(() => { this.scanSandbox() })
      ForEach(this.sandboxFiles, (fname: string) => {
        Text('📁 ' + fname)
          .fontSize(14).fontColor(this.text())
          .padding(10)
          .width('100%')
          .borderRadius(8)
          .backgroundColor(this.card())
          .border({ width: 1, color: this.sandboxPath === fname ? this.accent() : this.brd() })
          .margin({ bottom: 6 })
          .onClick(() => {
            this.sandboxPath = fname
            console.info('[P53] sandbox file selected: ' + fname)
          })
      })
      if (this.sourceKind === ImportSourceKind.MANUAL) {
        Text('手动录入 Cookie')
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.text())
          .margin({ bottom: 12 })
        TextInput({ placeholder: '域名 (如 example.com)' })
          .fontSize(14)
          .onChange((v: string) => { this.manualDomain = v })
          .margin({ bottom: 8 })
        TextInput({ placeholder: 'Cookie 名 (如 session_id)' })
          .fontSize(14)
          .onChange((v: string) => { this.manualCookieName = v })
          .margin({ bottom: 8 })
        TextInput({ placeholder: 'Cookie 值' })
          .fontSize(14)
          .onChange((v: string) => { this.manualCookieValue = v })
      } else {
        Text('点击「下一步」选择导出文件')
          .fontSize(15).fontColor(this.text())
          .margin({ bottom: 8 })
        Text('支持 .txt（Netscape）与 .json 格式，将自动识别')
          .fontSize(13).fontColor(this.text2())
        if (this.pickedFileName.length > 0) {
          Text(`已选: ${this.pickedFileName}`)
            .fontSize(13).fontColor(this.ok())
            .margin({ top: 8 })
        }
      }
      if (this.parseError.length > 0) {
        Text(this.parseError)
          .fontSize(13).fontColor('#F85149')
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---------- Step3 UI ----------
  @Builder
  StepPreview() {
    Column() {
      Text(`解析完成: ${this.previewRows.length} 个域名`)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.text())
        .margin({ bottom: 6 })
      Text('勾选要导入的域名（已全部默认勾选）')
        .fontSize(13).fontColor(this.text2())
        .margin({ bottom: 12 })
      // 敏感提醒
      Row() {
        Text('⚠ 敏感提醒：导入后 Cookie 将注入到对应域名的页面中')
          .fontSize(12).fontColor(this.warn())
          .layoutWeight(1)
      }
      .width('100%')
      .padding(10)
      .borderRadius(8)
      .backgroundColor(this.darkMode ? '#2D2200' : '#FFF8C5')
      .border({ width: 1, color: this.warn() })
      .margin({ bottom: 12 })

      ForEach(this.previewRows, (row: ImportPreviewRow) => {
        Row() {
          Checkbox()
            .select(this.selectedDomains.has(row.domain))
            .selectedColor(this.accent())
            .onChange((v: boolean) => {
              this.toggleDomain(row.domain)
            })
            .margin({ right: 10 })
          Column() {
            Row() {
              Text(row.domain)
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.text())
                .layoutWeight(1)
              if (row.duplicate) {
                Text('已存在(将覆盖)')
                  .fontSize(10).fontColor(this.warn())
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor(this.darkMode ? '#2D2200' : '#FFF8C5')
              }
            }
            .width('100%')
            Text(`${row.cookieCount} 条 Cookie · 最近过期: ${this.fmtExpiry(row.nearestExpiry)}`)
              .fontSize(12).fontColor(this.text2())
              .margin({ top: 2 })
            if (row.expiredCount > 0) {
              Text(`${row.expiredCount} 条已过期（导入时将跳过）`)
                .fontSize(11).fontColor('#F85149')
                .margin({ top: 2 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor(this.card())
        .border({ width: 1, color: this.brd() })
        .margin({ bottom: 8 })
        .onClick(() => {
          this.toggleDomain(row.domain)
        })
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---------- Step4 UI ----------
  @Builder
  StepResult() {
    Column() {
      if (this.importing) {
        LoadingProgress().width(40).height(40).color(this.accent())
        Text('正在导入并注入 Cookie…')
          .fontSize(14).fontColor(this.text2())
          .margin({ top: 12 })
      } else if (this.summary !== null) {
        Text('导入完成')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ok())
          .margin({ bottom: 12 })
        Row() {
          this.StatBlock(`${this.summary.totalImported}`, '成功', this.ok())
          this.StatBlock(`${this.summary.totalSkipped}`, '跳过', this.warn())
          this.StatBlock(`${this.summary.totalFailed}`, '失败', '#F85149')
        }
        .width('100%')
        .margin({ bottom: 16 })

        if (this.summary.totalFailed > 0 || this.summary.totalSkipped > 0) {
          Text('明细')
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.text())
            .margin({ bottom: 8 })
          ForEach(this.summary.results, (res: ImportDomainResult) => {
            Column() {
              Text(res.domain)
                .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.text())
              ForEach(res.reasons, (r: string) => {
                Text(`· ${r}`)
                  .fontSize(11).fontColor(this.text2())
                  .margin({ top: 2, left: 8 })
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(8)
            .borderRadius(8)
            .backgroundColor(this.card())
            .margin({ bottom: 6 })
          })
        }

        Button('完成')
          .fontSize(16).fontColor(Color.White)
          .backgroundColor(this.accent())
          .borderRadius(20)
          .height(44)
          .width('100%')
          .margin({ top: 16 })
          .onClick(() => { router.back() })
      } else {
        Text('准备导入…')
          .fontSize(14).fontColor(this.text2())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  StatBlock(v: string, label: string, c: string) {
    Column() {
      Text(v)
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(c)
      Text(label)
        .fontSize(12).fontColor(this.text2())
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}
