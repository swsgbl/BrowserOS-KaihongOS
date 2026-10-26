/**
 * P34-F: Skills 屏 —— 命令式技能台账（对标上游 claw-app up_skills.tsx 布局语义）
 * - 页头「Skills」extrabold 大标题 + 副标题 + New skill 圆角小钮
 * - 台账卡：Skill / Runs / Tokens saved / 操作列；行点击进详情覆盖态
 * - 存储：Preferences skills_store 键 skills_v1（JSON 数组）
 * - Run = AgentEngine.createAgent(name 去斜杠, 'about:blank', skill.prompt, ONCE)
 *   + runCount+1 落盘 + AppStorage 信号通知 BrowserShell 开侧栏后 router.back()
 * ArkTS: no any/unknown、no 解构、显式接口。
 */
import { preferences } from '@kit.ArkData'
import { I18n } from '../common/I18n'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'
import { AgentEngine } from '../service/AgentEngine'
import { RunStrategy } from '../common/Types'

/** P34-F: 技能条目（skills_v1 JSON 数组元素） */
interface SkillEntry {
  name: string
  description: string
  prompt: string
  runCount: number
  savedTokens: number
}

/** P34-F: 首次种子 3 条（name 命令式 / desc 中文 / prompt 可执行指令） */
function seedSkills(): SkillEntry[] {
  const arr: SkillEntry[] = []
  arr.push({
    name: '/summarize-page',
    description: I18n.t('skDefDesc1'),
    prompt: 'Read the current page and summarize it in exactly three bullet-point sentences in Chinese.',
    runCount: 0,
    savedTokens: 0
  })
  arr.push({
    name: '/watch-price',
    description: I18n.t('skDefDesc2'),
    prompt: 'Open the product page, find the current price, and report it. If the price changed since last check, highlight the change.',
    runCount: 0,
    savedTokens: 0
  })
  arr.push({
    name: '/fill-form',
    description: I18n.t('skDefDesc3'),
    prompt: 'Detect form fields on the current page and fill them with the profile data from settings, then stop for review.',
    runCount: 0,
    savedTokens: 0
  })
  return arr
}

@Entry
@Component
struct SkillsPage {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44
  @State skills: SkillEntry[] = []
  @State loaded: boolean = false
  @State detailName: string = ''
  @State showForm: boolean = false
  @State formName: string = ''
  @State formDesc: string = ''
  @State formPrompt: string = ''
  @State formHint: string = ''
  @State confirmDeleteName: string = ''
  @State toast: string = ''
  private prefs: preferences.Preferences | null = null

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  aboutToAppear(): void {
    console.info('[P34] SkillsPage mounted')
    const ctx = this.getUIContext().getHostContext()
    if (!ctx) {
      console.error('[P34] SkillsPage: no host context')
      this.loaded = true
      return
    }
    preferences.getPreferences(ctx, 'skills_store').then((p: preferences.Preferences) => {
      this.prefs = p
      const raw = p.getSync('skills_v1', '') as string
      this.skills = this.parseSkills(raw)
      if (this.skills.length === 0) {
        this.skills = seedSkills()
        this.persist()
      }
      this.loaded = true
      console.info('[P34] SkillsPage loaded ' + this.skills.length + ' skills')
    }).catch((e: Object) => {
      console.error('[P34] SkillsPage prefs init fail: ' + e)
      this.skills = seedSkills()
      this.loaded = true
    })
  }

  /** P34-F: skills_v1 JSON 反序列化（容错：坏行丢弃） */
  private parseSkills(raw: string): SkillEntry[] {
    if (raw.length === 0) {
      return []
    }
    try {
      const arr: Array<Record<string, Object>> = JSON.parse(raw) as Array<Record<string, Object>>
      const out: SkillEntry[] = []
      for (const r of arr) {
        const name = r['name'] as string
        if (typeof name !== 'string' || name.length === 0) {
          continue
        }
        const item: SkillEntry = {
          name: name,
          description: (r['description'] as string) ?? '',
          prompt: (r['prompt'] as string) ?? '',
          runCount: Number(r['runCount'] ?? 0),
          savedTokens: Number(r['savedTokens'] ?? 0)
        }
        out.push(item)
      }
      return out
    } catch (e) {
      console.error('[P34] skills_v1 parse fail: ' + e)
      return []
    }
  }

  /** P34-F: skills 落盘（JSON 数组） */
  private persist(): void {
    const p = this.prefs
    if (!p) {
      return
    }
    p.put('skills_v1', JSON.stringify(this.skills)).then(() => p.flush()).catch((e: Object) => {
      console.error('[P34] skills persist fail: ' + e)
    })
  }

  /** name 显示：自动补 / 前缀 */
  private displayName(name: string): string {
    return name.startsWith('/') ? name : '/' + name
  }

  /** agent 名：去 / 前缀 */
  private agentName(name: string): string {
    return name.startsWith('/') ? name.substring(1) : name
  }

  /** Run：createAgent ONCE + runCount+1 落盘 + 信号通知 shell 开侧栏 */
  private runSkill(skill: SkillEntry): void {
    console.info('[P34] run skill: ' + skill.name)
    const cfg = AgentEngine.createAgent(this.agentName(skill.name), 'about:blank', skill.prompt, RunStrategy.ONCE)
    if (cfg) {
      skill.runCount = skill.runCount + 1
      this.skills = [...this.skills]
      this.persist()
      // P34-F: AppStorage 信号（BrowserShell @StorageLink @Watch）+ 返回 shell 展示侧栏运行
      const prev: number = AppStorage.get<number>('p34_skills_run_signal') ?? 0
      AppStorage.setOrCreate('p34_skills_run_signal', prev + 1)
      this.showToast(I18n.t('skStarted') + this.displayName(skill.name))
      setTimeout(() => {
        router.back()
      }, 600)
      console.info('[P34] skill agent created, runCount=' + skill.runCount)
    } else {
      this.showToast(I18n.t('skStartFail'))
    }
  }

  private deleteSkill(name: string): void {
    console.info('[P34] delete skill: ' + name)
    this.skills = this.skills.filter((s: SkillEntry) => s.name !== name)
    this.persist()
    if (this.detailName === name) {
      this.detailName = ''
    }
    this.confirmDeleteName = ''
    this.showToast(I18n.t('skDeleted') + this.displayName(name))
  }

  private saveNewSkill(): void {
    let name = this.formName.trim()
    if (name.length === 0) {
      this.formHint = I18n.t('skNameRequired')
      return
    }
    if (!name.startsWith('/')) {
      name = '/' + name
    }
    if (this.skills.some((s: SkillEntry) => s.name === name)) {
      this.formHint = I18n.t('skExists')
      return
    }
    const prompt = this.formPrompt.trim()
    if (prompt.length === 0) {
      this.formHint = I18n.t('skPromptRequired')
      return
    }
    const item: SkillEntry = {
      name: name,
      description: this.formDesc.trim(),
      prompt: prompt,
      runCount: 0,
      savedTokens: 0
    }
    this.skills = [item, ...this.skills]
    this.persist()
    this.showForm = false
    this.formName = ''
    this.formDesc = ''
    this.formPrompt = ''
    this.formHint = ''
    this.showToast(I18n.t('skSaved') + name)
    console.info('[P34] skill saved: ' + name)
  }

  private showToast(text: string): void {
    this.toast = text
    setTimeout(() => { this.toast = '' }, 2000)
  }

  private findSkill(name: string): SkillEntry | null {
    for (const s of this.skills) {
      if (s.name === name) {
        return s
      }
    }
    return null
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('SkillsPage theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Stack() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }

      Column() {
        this.Header()
        if (!this.loaded) {
          Column() {
            LoadingProgress().width(28).height(28).color(this.pal().text2)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.skills.length === 0) {
          Column() {
            Text(I18n.t('skEmpty'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().text2)
            Text(I18n.t('skEmptyHint'))
              .fontSize(11)
              .fontColor(this.pal().text2)
              .margin({ top: 6 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            this.LedgerCard()
          }
          .layoutWeight(1)
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().surfaceAlt)

      // P34-F: 详情覆盖态
      if (this.detailName.length > 0) {
        this.DetailOverlay()
      }

      // P34-F: New skill 表单弹层
      if (this.showForm) {
        this.SkillFormDialog()
      }

      // P34-F: Delete 二次确认
      if (this.confirmDeleteName.length > 0) {
        this.DeleteConfirmDialog()
      }

      // toast
      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor('#CC1F1F22')
          .borderRadius(16)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .position({ x: '50%', y: '88%' })
          .translate({ x: -60 })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 页头：Skills 大标题 + 副标题 + New skill 钮 */
  @Builder
  Header(): void {
    Row() {
      Column() {
        Text(I18n.t('skillsTitle'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
        Text(I18n.t('skillsSubtitle'))
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(I18n.t('skNewSkill'))
        .fontSize(12)
        .height(32)
        .backgroundColor('#2E6FE8')
        .fontColor('#FFFFFF')
        .borderRadius(16)
        .onClick(() => {
          this.showForm = true
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 10 })
    .alignItems(VerticalAlign.Top)
  }

  /** 台账卡：表头 + 行（mono 蓝名 + desc / Runs / Tokens saved / Run+Delete） */
  @Builder
  LedgerCard(): void {
    Column() {
      // 表头
      Row() {
        Text(I18n.t('skSkill'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text2)
          .layoutWeight(1)
        Text(I18n.t('skRuns'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text2)
          .width(48)
          .textAlign(TextAlign.End)
        Text(I18n.t('skTokensSaved'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text2)
          .width(90)
          .textAlign(TextAlign.End)
        Text('')
          .width(110)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 8 })
      .border({ width: { bottom: 1 }, color: this.pal().border })

      ForEach(this.skills, (s: SkillEntry) => {
        Row() {
          Column() {
            Text(this.displayName(s.name))
              .fontSize(13)
              .fontFamily('monospace')
              .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(s.description)
              .fontSize(11)
              .fontColor(this.pal().text2)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .onClick(() => {
            console.info('[P34] open skill detail: ' + s.name)
            this.detailName = s.name
          })

          Text(s.runCount.toString())
            .fontSize(13)
            .fontColor(this.pal().text)
            .width(48)
            .textAlign(TextAlign.End)

          Column() {
            if (s.savedTokens > 0) {
              Text(I18n.t('skSavedN').replace('{n}', `${s.savedTokens}`))
                .fontSize(13)
                .fontColor(this.pal().text)
                .textAlign(TextAlign.End)
            } else {
              Text(I18n.t('skNotMeasured'))
                .fontSize(12)
                .fontColor(this.pal().text2)
                .textAlign(TextAlign.End)
            }
          }
          .width(90)
          .alignItems(HorizontalAlign.End)

          Row() {
            Button(I18n.t('skRun'))
              .fontSize(11)
              .height(26)
              .backgroundColor('#22A06B')
              .fontColor('#FFFFFF')
              .borderRadius(13)
              .onClick(() => {
                this.runSkill(s)
              })
            Text(I18n.t('delete'))
              .fontSize(11)
              .fontColor('#C5221F')
              .margin({ left: 10 })
              .onClick(() => {
                this.confirmDeleteName = s.name
              })
          }
          .width(110)
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .border({ width: { bottom: 1 }, color: this.pal().border })
        .onClick(() => {
          console.info('[P34] open skill detail (row): ' + s.name)
          this.detailName = s.name
        })
      }, (s: SkillEntry) => s.name + '_' + s.runCount)
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor(this.pal().surface)
    .margin({ left: 16, right: 16, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 详情覆盖态：全文 + Run 大钮 + 返回 */
  @Builder
  DetailOverlay(): void {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')

      Column() {
        Scroll() {
          Column() {
            Row() {
              Button(I18n.t('skBack'))
                .fontSize(12)
                .height(30)
                .backgroundColor(this.pal().surfaceInput)
                .fontColor(this.pal().text)
                .borderRadius(15)
                .onClick(() => {
                  this.detailName = ''
                })
              Blank()
              Button(I18n.t('skRun'))
                .fontSize(13)
                .height(32)
                .backgroundColor('#22A06B')
                .fontColor('#FFFFFF')
                .borderRadius(16)
                .onClick(() => {
                  const s = this.findSkill(this.detailName)
                  if (s) {
                    this.runSkill(s)
                  }
                })
            }
            .width('100%')

            Text(this.displayName(this.detailName))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
              .margin({ top: 16 })
              .alignSelf(ItemAlign.Start)

            Text(I18n.t('skDesc'))
              .fontSize(11)
              .fontColor(this.pal().text2)
              .margin({ top: 14 })
              .alignSelf(ItemAlign.Start)
            Text(this.findSkill(this.detailName)?.description ?? '')
              .fontSize(13)
              .fontColor(this.pal().text)
              .margin({ top: 4 })
              .alignSelf(ItemAlign.Start)

            Text(I18n.t('skPrompt'))
              .fontSize(11)
              .fontColor(this.pal().text2)
              .margin({ top: 14 })
              .alignSelf(ItemAlign.Start)
            Text(this.findSkill(this.detailName)?.prompt ?? '')
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(this.pal().text)
              .backgroundColor(this.pal().surfaceInput)
              .borderRadius(8)
              .padding(10)
              .margin({ top: 4 })
              .alignSelf(ItemAlign.Start)

            Row() {
              Text(I18n.t('skRunsN').replace('{n}', `${this.findSkill(this.detailName)?.runCount ?? 0}`))
                .fontSize(11)
                .fontColor(this.pal().text2)
              Text(' · ')
                .fontSize(11)
                .fontColor(this.pal().text2)
              Text((this.findSkill(this.detailName)?.savedTokens ?? 0) > 0 ? I18n.t('skSavedN').replace('{n}', `${this.findSkill(this.detailName)?.savedTokens}`) : I18n.t('skNotMeasured'))
                .fontSize(11)
                .fontColor(this.pal().text2)
            }
            .margin({ top: 14 })
          }
          .width('100%')
          .padding(16)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
      .width('86%')
      .height('70%')
      .borderRadius(14)
      .backgroundColor(this.pal().surface)
    }
    .width('100%')
    .height('100%')
  }

  /** New skill 表单弹层 */
  @Builder
  SkillFormDialog(): void {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showForm = false
        })

      Column() {
        Text(I18n.t('skNewSkill'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)

        Text(I18n.t('skNameLabel'))
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ top: 12 })
          .alignSelf(ItemAlign.Start)
        TextInput({ text: this.formName, placeholder: '/my-skill' })
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().text2)
          .width('100%')
          .height(36)
          .backgroundColor(this.pal().surfaceInput)
          .borderRadius(8)
          .onChange((v: string) => { this.formName = v })

        Text(I18n.t('skDescLabel'))
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ top: 10 })
          .alignSelf(ItemAlign.Start)
        TextInput({ text: this.formDesc, placeholder: I18n.t('skDescPh') })
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().text2)
          .width('100%')
          .height(36)
          .backgroundColor(this.pal().surfaceInput)
          .borderRadius(8)
          .onChange((v: string) => { this.formDesc = v })

        Text(I18n.t('skPromptLabel'))
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ top: 10 })
          .alignSelf(ItemAlign.Start)
        TextArea({ text: this.formPrompt, placeholder: I18n.t('skPromptPh') })
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().text2)
          .width('100%')
          .constraintSize({ minHeight: 72 })
          .backgroundColor(this.pal().surfaceInput)
          .borderRadius(8)
          .margin({ top: 4 })
          .onChange((v: string) => { this.formPrompt = v })

        if (this.formHint.length > 0) {
          Text(this.formHint)
            .fontSize(11)
            .fontColor('#C5221F')
            .margin({ top: 8 })
        }

        Row() {
          Button(I18n.t('save'))
            .fontSize(12)
            .height(32)
            .backgroundColor('#2E6FE8')
            .fontColor('#FFFFFF')
            .borderRadius(8)
            .onClick(() => {
              this.saveNewSkill()
            })
          Button(I18n.t('cancel'))
            .fontSize(12)
            .height(32)
            .backgroundColor(this.pal().surfaceInput)
            .fontColor(this.pal().text)
            .borderRadius(8)
            .margin({ left: 10 })
            .onClick(() => {
              this.showForm = false
            })
        }
        .margin({ top: 14 })
      }
      .width('86%')
      .padding(16)
      .borderRadius(14)
      .backgroundColor(this.pal().surface)
    }
    .width('100%')
    .height('100%')
  }

  /** Delete 二次确认 */
  @Builder
  DeleteConfirmDialog(): void {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')

      Column() {
        Text(I18n.t('skDeleteSkill'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
        Text(I18n.t('skDeletePre') + this.displayName(this.confirmDeleteName) + I18n.t('skDeleteConfirm'))
          .fontSize(12)
          .fontColor(this.pal().text2)
          .margin({ top: 10 })

        Row() {
          Button(I18n.t('cancel'))
            .fontSize(12)
            .height(32)
            .backgroundColor(this.pal().surfaceInput)
            .fontColor(this.pal().text)
            .borderRadius(8)
            .onClick(() => {
              this.confirmDeleteName = ''
            })
          Button(I18n.t('delete'))
            .fontSize(12)
            .height(32)
            .backgroundColor('#C5221F')
            .fontColor('#FFFFFF')
            .borderRadius(8)
            .margin({ left: 10 })
            .onClick(() => {
              this.deleteSkill(this.confirmDeleteName)
            })
        }
        .margin({ top: 16 })
      }
      .width('76%')
      .padding(16)
      .borderRadius(14)
      .backgroundColor(this.pal().surface)
    }
    .width('100%')
    .height('100%')
  }
}
