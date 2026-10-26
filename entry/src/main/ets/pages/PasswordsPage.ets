/**
 * P47-B: 密码管理器页面 —— 列表(按域名分组)/搜索/编辑/删除/全部清除/Bitwarden 导入导出
 */
import { CredentialStore, Credential } from '../service/CredentialStore'
import { router } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'

interface DomainGroup {
  domain: string
  creds: Credential[]
}

@Entry
@Component
struct PasswordsPage {
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false
  @State themeVersion: number = 0
  @State groups: DomainGroup[] = []
  @State query: string = ''
  @State totalCount: number = 0
  // 编辑弹层
  @State editOpen: boolean = false
  @State editId: string = ''
  @State editDomain: string = ''
  @State editUsername: string = ''
  @State editPassword: string = ''
  @State showPassword: boolean = false
  // 导入弹层
  @State importOpen: boolean = false
  @State importText: string = ''
  @State importResult: string = ''

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

  onThemeFlip(): void {
    this.themeVersion++
  }

  aboutToAppear(): void {
    this.refresh()
  }

  private refresh(): void {
    const all = CredentialStore.getAll()
    this.totalCount = all.length
    const q = this.query.trim().toLowerCase()
    const filtered = q.length === 0 ? all : all.filter((c: Credential): boolean =>
      c.domain.toLowerCase().includes(q) || c.username.toLowerCase().includes(q))
    const byDomain = new Map<string, Credential[]>()
    for (const c of filtered) {
      let arr = byDomain.get(c.domain)
      if (!arr) {
        arr = []
        byDomain.set(c.domain, arr)
      }
      arr.push(c)
    }
    const gs: DomainGroup[] = []
    byDomain.forEach((v: Credential[], k: string) => {
      gs.push({ domain: k, creds: v })
    })
    gs.sort((a: DomainGroup, b: DomainGroup): number => a.domain.localeCompare(b.domain))
    this.groups = gs
  }

  private openAdd(): void {
    this.editId = ''
    this.editDomain = ''
    this.editUsername = ''
    this.editPassword = ''
    this.showPassword = false
    this.editOpen = true
  }

  private openEdit(c: Credential): void {
    this.editId = c.id
    this.editDomain = c.domain
    this.editUsername = c.username
    this.editPassword = c.password
    this.showPassword = false
    this.editOpen = true
  }

  private saveEdit(): void {
    if (this.editDomain.trim().length === 0 || this.editUsername.trim().length === 0) {
      return
    }
    if (this.editId.length === 0) {
      CredentialStore.add(this.editDomain.trim(), this.editUsername.trim(), this.editPassword)
      this.editOpen = false
      this.refresh()
    } else {
      CredentialStore.update(this.editId, this.editDomain.trim(), this.editUsername.trim(), this.editPassword)
      this.editOpen = false
      this.refresh()
    }
  }

  private removeCred(id: string): void {
    CredentialStore.remove(id)
    this.refresh()
  }

  private clearAll(): void {
    CredentialStore.clearAll()
    this.refresh()
  }

  private doImport(): void {
    const r: number = CredentialStore.importBitwardenJson(this.importText)
    if (r < 0) {
      this.importResult = '导入失败：非 Bitwarden JSON 格式'
      return
    }
    this.importResult = '已导入 ' + r + ' 条'
    this.refresh()
  }

  private doExport(): void {
    // 导出到剪贴板（VM 无文件选择器，剪贴板最直接）
    const json = CredentialStore.exportBitwardenJson()
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json)
    pasteboard.getSystemPasteboard().setData(data)
    this.importResult = '已复制 ' + json.length + ' 字节到剪贴板'
  }

  build(): void {
    Stack() {
      Column() {
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // 顶栏
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($rawfile('ic_back.svg'))
              .width(20).height(20)
              .fillColor(this.text2())
              .draggable(false)
          }
          .width(36).height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back() })
          Text('密码管理器')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.text())
            .layoutWeight(1)
            .margin({ left: 4 })
          Text(this.totalCount + ' 条')
            .fontSize(12)
            .fontColor(this.text2())
            .margin({ right: 8 })
          Button('导入')
            .fontSize(13)
            .height(32)
            .backgroundColor(this.card())
            .fontColor(this.text())
            .onClick(() => {
              this.importOpen = true
              this.importResult = ''
            })
          Button('清空')
            .fontSize(13)
            .height(32)
            .backgroundColor(this.card())
            .fontColor('#C5221F')
            .margin({ left: 8 })
            .onClick(() => { this.clearAll() })
        }
        .width('100%')
        .height(52)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.bg())

        // 搜索
        Row() {
          Image($rawfile('ic_search.svg'))
            .width(16).height(16)
            .fillColor(this.text2())
            .draggable(false)
            .margin({ left: 10 })
          TextInput({ text: this.query, placeholder: '搜索域名或用户名' })
            .fontSize(13)
            .fontColor(this.text())
            .placeholderColor(this.text2())
            .layoutWeight(1)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onChange((v: string) => {
              this.query = v
              this.refresh()
            })
        }
        .width('94%')
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.card())
        .margin({ top: 10 })

        // 列表
        Scroll() {
          Column() {
            if (this.groups.length === 0) {
              Column() {
                Image($rawfile('ic_lock.svg'))
                  .width(40).height(40)
                  .fillColor(this.text2())
                  .draggable(false)
                Text('暂无保存的密码')
                  .fontSize(14)
                  .fontColor(this.text2())
                  .margin({ top: 12 })
                Text('登录网站时可保存，或从 Bitwarden 导入')
                  .fontSize(12)
                  .fontColor(this.text2())
                  .margin({ top: 4 })
              }
              .width('100%')
              .margin({ top: 120 })
              .alignItems(HorizontalAlign.Center)
            }
            ForEach(this.groups, (g: DomainGroup) => {
              Column() {
                Text(g.domain)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.text2())
                  .alignSelf(ItemAlign.Start)
                  .padding({ left: 4, top: 8, bottom: 4 })
                ForEach(g.creds, (c: Credential) => {
                  Row() {
                    Column() {
                      Text(c.username)
                        .fontSize(14)
                        .fontColor(this.text())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.showPassword ? c.password : '••••••••')
                        .fontSize(12)
                        .fontColor(this.text2())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Button({ type: ButtonType.Normal }) {
                      Image($rawfile(this.showPassword ? 'ic_info.svg' : 'ic_lock.svg'))
                        .width(16).height(16)
                        .fillColor(this.text2())
                        .draggable(false)
                    }
                    .width(32).height(32)
                    .backgroundColor(Color.Transparent)
                    .accessibilityText('显示密码')
                    .onClick(() => { this.showPassword = !this.showPassword })

                    Button({ type: ButtonType.Normal }) {
                      Image($rawfile('ic_edit.svg'))
                        .width(16).height(16)
                        .fillColor(this.text2())
                        .draggable(false)
                    }
                    .width(32).height(32)
                    .backgroundColor(Color.Transparent)
                    .accessibilityText('编辑')
                    .onClick(() => { this.openEdit(c) })

                    Button({ type: ButtonType.Normal }) {
                      Image($rawfile('ic_close.svg'))
                        .width(16).height(16)
                        .fillColor('#C5221F')
                        .draggable(false)
                    }
                    .width(32).height(32)
                    .backgroundColor(Color.Transparent)
                    .accessibilityText('删除')
                    .onClick(() => { this.removeCred(c.id) })
                  }
                  .width('100%')
                  .height(56)
                  .padding({ left: 12, right: 4 })
                  .borderRadius(8)
                  .backgroundColor(this.card())
                  .margin({ top: 2 })
                }, (c: Credential) => c.id)
              }
              .width('94%')
              .margin({ top: 6 })
            }, (g: DomainGroup) => g.domain + '_' + g.creds.length)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bg())

      // 添加按钮（右下角浮动）
      Button({ type: ButtonType.Normal }) {
        Image($rawfile('ic_add.svg'))
          .width(22).height(22)
          .fillColor('#FFFFFF')
          .draggable(false)
      }
      .width(52).height(52)
      .borderRadius(26)
      .backgroundColor(this.accent())
      .position({ x: '86%', y: '88%' })
      .accessibilityText('添加密码')
      .onClick(() => { this.openAdd() })

      // 编辑/新增弹层
      if (this.editOpen) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => { this.editOpen = false })
        Column() {
          Text(this.editId.length > 0 ? '编辑密码' : '添加密码')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.text())
            .alignSelf(ItemAlign.Start)
          Text('域名')
            .fontSize(12)
            .fontColor(this.text2())
            .margin({ top: 12, bottom: 4 })
            .alignSelf(ItemAlign.Start)
          TextInput({ text: this.editDomain, placeholder: 'example.com' })
            .fontSize(13)
            .fontColor(this.text())
            .width('100%')
            .height(38)
            .backgroundColor(this.card())
            .borderRadius(8)
            .onChange((v: string) => { this.editDomain = v })
          Text('用户名')
            .fontSize(12)
            .fontColor(this.text2())
            .margin({ top: 10, bottom: 4 })
            .alignSelf(ItemAlign.Start)
          TextInput({ text: this.editUsername, placeholder: 'user@example.com' })
            .fontSize(13)
            .fontColor(this.text())
            .width('100%')
            .height(38)
            .backgroundColor(this.card())
            .borderRadius(8)
            .onChange((v: string) => { this.editUsername = v })
          Text('密码')
            .fontSize(12)
            .fontColor(this.text2())
            .margin({ top: 10, bottom: 4 })
            .alignSelf(ItemAlign.Start)
          TextInput({ text: this.editPassword, placeholder: '••••••' })
            .fontSize(13)
            .fontColor(this.text())
            .width('100%')
            .height(38)
            .backgroundColor(this.card())
            .borderRadius(8)
            .type(InputType.Password)
            .onChange((v: string) => { this.editPassword = v })
          Row() {
            Button('取消')
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .backgroundColor(this.card())
              .fontColor(this.text())
              .onClick(() => { this.editOpen = false })
            Button('保存')
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .backgroundColor(this.accent())
              .fontColor('#FFFFFF')
              .margin({ left: 10 })
              .onClick(() => { this.saveEdit() })
          }
          .width('100%')
          .margin({ top: 16 })
        }
        .width('80%')
        .padding(18)
        .borderRadius(14)
        .backgroundColor(this.bg())
        .alignItems(HorizontalAlign.Center)
      }

      // Bitwarden 导入弹层
      if (this.importOpen) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => { this.importOpen = false })
        Column() {
          Text('从 Bitwarden 导入')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.text())
            .alignSelf(ItemAlign.Start)
          Text('粘贴 Bitwarden 导出的 JSON（未加密格式）')
            .fontSize(12)
            .fontColor(this.text2())
            .margin({ top: 6 })
            .alignSelf(ItemAlign.Start)
          TextArea({ text: this.importText, placeholder: '{"encrypted":false,"items":[...]}' })
            .fontSize(11)
            .fontColor(this.text())
            .width('100%')
            .height(140)
            .backgroundColor(this.card())
            .borderRadius(8)
            .margin({ top: 12 })
            .onChange((v: string) => { this.importText = v })
          if (this.importResult.length > 0) {
            Text(this.importResult)
              .fontSize(12)
              .fontColor(this.importResult.startsWith('已') ? '#22C55E' : '#C5221F')
              .margin({ top: 8 })
          }
          Row() {
            Button('导出到剪贴板')
              .fontSize(12)
              .height(34)
              .layoutWeight(1)
              .backgroundColor(this.card())
              .fontColor(this.text())
              .onClick(() => { this.doExport() })
            Button('导入')
              .fontSize(13)
              .height(34)
              .layoutWeight(1)
              .backgroundColor(this.accent())
              .fontColor('#FFFFFF')
              .margin({ left: 10 })
              .onClick(() => { this.doImport() })
          }
          .width('100%')
          .margin({ top: 14 })
        }
        .width('80%')
        .padding(18)
        .borderRadius(14)
        .backgroundColor(this.bg())
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
