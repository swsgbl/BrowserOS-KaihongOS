/**
 * P9-B: Agent 侧边面板（ref1 一比一复刻）
 * 右侧 360vp 常驻面板：顶部标题栏（Agent + 模型下拉 + ⚙）+ 消息气泡列表
 * + 底部多行输入 + 发送。发送 = AgentEngine.createAgent（与 Dashboard 磁贴联动）。
 */
import { AgentEngine } from '../service/AgentEngine'
import { I18n } from '../common/I18n'
import { SessionManager } from '../service/SessionManager'
import { SessionRecord } from '../model/SessionRecord'
import { ConfigManager } from '../storage/ConfigManager'
import { RunStrategy, AgentStatus } from '../common/Types'
import { AgentStatusInfo } from '../model/AgentStatus'
import { Palette } from '../common/Palette'
import { router } from '@kit.ArkUI'
import { preferences } from '@kit.ArkData'
import { BusinessError } from '@kit.BasicServicesKit'
import { TabManager } from '../service/TabManager'
import { LLMClient, LLMChatMessage, LLMRequestOptions } from '../service/LLMClient'
import { JSBridgeInjector } from '../protocol/JSBridgeInjector'
import { JtbdStore } from '../pages/JtbdSurveyPage'
import { DeviceAgentStore, DeviceAgentEntry, DeviceAgentTask } from '../service/DeviceAgentStore'

interface ChatMessage {
  role: string // 'user' | 'agent' | 'hint'
  text: string
  agentId: string
}

/** P24b: 起手提示词(对标上游 starter-prompts.ts: display 短标签 + prompt 完整指令) */
class StarterPrompt {
  display: string = ''
  prompt: string = ''
  constructor(display: string, prompt: string) {
    this.display = display
    this.prompt = prompt
  }
}

/** P33-A: 页面选中文本上下文(对标上游 selectedTextStorage 条目) */
class PageSelection {
  text: string = ''
  pageUrl: string = ''
  pageTitle: string = ''
  timestamp: number = 0
}

/** P33-C: 附加标签页 chip 数据(对标上游 ChatAttachedTabs 的 tab 条目) */
class AttachedTabInfo {
  tabId: string = ''
  title: string = ''
  url: string = ''
}

function defaultStarterPrompts(): StarterPrompt[] {
  return [
    new StarterPrompt(I18n.t('asSummary'), 'Read the current tab and summarize it in bullet points'),
    new StarterPrompt(I18n.t('asWhatIs'), 'Read the current tab and describe what it is about in 1-2 lines'),
    new StarterPrompt(I18n.t('asComments'), 'Read the current tab and extract comments as bullet points')
  ]
}

@Component
export struct AgentSidePanel {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State messages: ChatMessage[] = []
  @State inputText: string = ''
  @State modelSelection: number = 0
  /** P67: 设备智能体注册表 + 选中名（空串=内置）+ 任务态轮询 */
  @State daAgents: DeviceAgentEntry[] = []
  @State daSel: string = ''
  @State daModelOpen: boolean = false
  private daTimer: number = -1
  private daTaskIds: Set<string> = new Set<string>()
  @State agents: AgentStatusInfo[] = []
  @State showModelDropdown: boolean = false
  /** P24b: 起手提示词(Preferences 持久化, 容错回默认) */
  @State starters: StarterPrompt[] = defaultStarterPrompts()
  /** P24b: 自定义提示词内联编辑器开合 */
  @State editingStarters: boolean = false
  /** P24b: 编辑器三对输入(display/prompt 各3) */
  @State edDisplay0: string = ''
  @State edPrompt0: string = ''
  @State edDisplay1: string = ''
  @State edPrompt1: string = ''
  @State edDisplay2: string = ''
  @State edPrompt2: string = ''
  /** P24c: 最近派发且仍在运行的 agentId(停止钮目标) */
  @State lastRunningAgentId: string = ''
  /** P21b: 面板双视图——chat(默认,上游 index 路由) / history(上游 /history 路由) */
  @State panelView: string = 'chat'
  /** P21b: history 视图数据(时间倒序,getSessionListAsync) */
  @State historySessions: SessionRecord[] = []
  /** P21b: history 加载态(防止闪空态) */
  @State historyLoading: boolean = false
  /** P33-B: 聊天模式 'chat'(单轮只读) / 'agent'(工具循环,默认)。Preferences key chat_mode 持久化 */
  @State chatMode: string = 'agent'
  /** P33-A: 当前抓到的页面选中文本(输入框上方 chip 展示,可丢弃) */
  @State pageSelection: PageSelection | null = null
  /** P33-C: 附加的网页标签 chip;用户点 X 后置 suppressAutoAttach 直到活动 tab 切换 */
  @State attachedTab: AttachedTabInfo | null = null
  @State suppressAutoAttach: boolean = false
  /** P33-B: chat 模式请求进行中(发送钮转态) */
  @State chatBusy: boolean = false
  /** P35-A: jtbd 弹窗状态。shownCount=已弹次数; dontShow=勾选不再显示; surveyTaken=已答 */
  @State jtbdShownCount: number = 0
  @State jtbdDontShow: boolean = false
  @State jtbdSurveyTaken: boolean = false
  @State jtbdPopupVisible: boolean = false
  @State jtbdCheckboxChecked: boolean = false
  /** P35-A: 本次会话是否已弹过（防重复） */
  private jtbdFiredThisSession: boolean = false
  /** P35-A: 上游 MESSAGE_THRESHOLD=10（user+agent 消息计数） */
  private readonly JTBD_MESSAGE_THRESHOLD: number = 10
  /** P35-A: 上游 DONT_SHOW_AGAIN_AFTER=2（shownCount≥2 起显示复选框） */
  private readonly JTBD_DONT_SHOW_AFTER: number = 2
  onClose: () => void = () => {}
  /** P19a: 已回流过终态的 agent（去重，避免轮询重复推气泡） */
  private settledAgents: Set<string> = new Set()
  /** P19a: 终态轮询句柄（aboutToDisappear 必清） */
  private pollTimer: number = -1
  /** P33-A/C: 上下文轮询句柄(选区 + 附加 tab) */
  private ctxPollTimer: number = -1
  /** P33-C: 上次见过的活动 tab(切换检测,解除 suppressAutoAttach) */
  private lastSeenActiveTabId: string = ''
  /** P19a: 消息列表滚动控制器（答案回流后滚底） */
  private scroller: Scroller = new Scroller()

  /** P67: 载入设备智能体注册表（UI 气泡态展示用） */
  private loadDaAgents(): void {
    DeviceAgentStore.listAgents().then((list: DeviceAgentEntry[]) => {
      this.daAgents = list
      if (this.daSel.length > 0) {
        let found = false
        for (const a of list) {
          if (a.name === this.daSel) {
            found = true
            break
          }
        }
        if (!found) {
          this.daSel = ''
        }
      }
    }).catch(() => {
    })
  }

  /** P67: 设备智能体注册表 5s 轮询（在线态 + 任务完成态） */
  private startDaPolling(): void {
    if (this.daTimer >= 0) {
      return
    }
    this.daTimer = setInterval(() => {
      this.loadDaAgents()
      this.pollDaTasks()
    }, 5000)
  }

  private stopDaPolling(): void {
    if (this.daTimer >= 0) {
      clearInterval(this.daTimer)
      this.daTimer = -1
    }
  }

  /** P67: 已派发设备任务完成态轮询 → 回流气泡 */
  private pollDaTasks(): void {
    if (this.daTaskIds.size === 0) {
      return
    }
    const ids = Array.from(this.daTaskIds)
    for (const id of ids) {
      DeviceAgentStore.getTask(id).then((t: DeviceAgentTask | null) => {
        if (t === null) {
          this.daTaskIds.delete(id)
          return
        }
        if (t.status === 'completed') {
          this.daTaskIds.delete(id)
          const text = t.result.length > 500 ? t.result.substring(0, 500) + '…' : t.result
          this.messages.push({ role: 'agent', text: text.length > 0 ? text : I18n.t('daDone'), agentId: 'da_' + id })
          console.info('[P67] da task answer reflux: ' + id + ' len=' + t.result.length)
          setTimeout(() => {
            this.scroller.scrollEdge(Edge.Bottom)
          }, 50)
        } else if (t.status === 'failed') {
          this.daTaskIds.delete(id)
          this.messages.push({ role: 'hint', text: I18n.t('daFailed') + (t.result.length > 0 ? t.result : 'unknown'), agentId: 'da_' + id })
          console.info('[P67] da task fail reflux: ' + id)
          setTimeout(() => {
            this.scroller.scrollEdge(Edge.Bottom)
          }, 50)
        }
      })
    }
  }

  /** P67: 提交任务给设备智能体（收件箱） */
  private dispatchDaTask(task: string, ctxBlock: string): void {
    const tabId = TabManager.getActiveTabId()
    const tab = tabId.length > 0 ? TabManager.getTab(tabId) : null
    const url = tab !== null && !tab.isDashboard ? tab.currentUrl : ''
    const title = tab !== null ? tab.title : ''
    const sel = this.pageSelection !== null ? this.pageSelection.text : ''
    this.messages.push({ role: 'hint', text: I18n.t('daTaskSent') + this.daSel + ' · ' + I18n.t('daWaiting'), agentId: '' })
    const fullTask = ctxBlock.length > 0 ? task + '\n\n[附加上下文]\n' + ctxBlock : task
    DeviceAgentStore.createTask(this.daSel, fullTask, url, title, sel).then((t) => {
      console.info('[P67] sidepanel da task dispatched: ' + t.taskId + ' agent=' + this.daSel)
      this.daTaskIds.add(t.taskId)
      this.pollDaTasks()
    })
  }

  private modelOptions(): string[] {
    return ['agnes-3.0-flash', 'agnes-3.0-pro', 'glm-4.7', I18n.t('asCustomCfg'), I18n.t('asManageProviders')]
  }

  aboutToAppear(): void {
    this.agents = AgentEngine.getAllAgentStatus()
    this.messages.push({
      role: 'hint',
      text: I18n.t('asInputPh'),
      agentId: ''
    })
    console.info('AgentSidePanel mounted, agents=' + this.agents.length)
    this.loadStarterPrompts()
    this.startSettlePolling()
    this.loadChatMode()
    this.startCtxPolling()
    this.loadDaAgents()
    this.startDaPolling()
    this.loadJtbdState()
  }

  /** P35-A: 载入 jtbd_store（shownCount/dontShow/surveyTaken） */
  private loadJtbdState(): void {
    const ctx = getContext(this)
    JtbdStore.read(ctx).then((state: Record<string, Object>) => {
      this.jtbdShownCount = state['shownCount'] !== undefined ? state['shownCount'] as number : 0
      this.jtbdDontShow = state['dontShow'] === true
      this.jtbdSurveyTaken = state['surveyTaken'] === true
      console.info('[P35] jtbd state loaded: shownCount=' + this.jtbdShownCount + ' dontShow=' + this.jtbdDontShow + ' taken=' + this.jtbdSurveyTaken)
    })
  }

  /** P35-A: 消息计数达标后触发弹窗（user+agent 角色计入,hint 不计） */
  private maybeFireJtbdPopup(): void {
    if (this.jtbdFiredThisSession || this.jtbdPopupVisible) {
      return
    }
    if (this.jtbdDontShow || this.jtbdSurveyTaken) {
      return
    }
    let count = 0
    for (const m of this.messages) {
      if (m.role === 'user' || m.role === 'agent') {
        count++
      }
    }
    if (count < this.JTBD_MESSAGE_THRESHOLD) {
      return
    }
    this.jtbdFiredThisSession = true
    this.jtbdPopupVisible = true
    this.jtbdCheckboxChecked = false
    console.info('[P35] jtbd popup fired at message count=' + count + ' shownCount=' + this.jtbdShownCount)
  }

  /** P35-A: Maybe Later/X 关闭——shownCount+1 持久化; 勾选则 dontShow=true */
  private dismissJtbd(dontShowAgain: boolean): void {
    this.jtbdPopupVisible = false
    const nextCount = this.jtbdShownCount + 1
    this.jtbdShownCount = nextCount
    const patch: Record<string, Object> = { 'shownCount': nextCount }
    if (dontShowAgain) {
      this.jtbdDontShow = true
      patch['dontShow'] = true
    }
    console.info('[P35] jtbd dismissed: shownCount->' + nextCount + ' dontShowAgain=' + dontShowAgain)
    const ctx = getContext(this)
    JtbdStore.write(ctx, patch).then(() => {
      // dontShow=false 时重置本会话标记,下个阈值周期(再+10条)可再弹
      if (!dontShowAgain) {
        this.jtbdFiredThisSession = false
      }
    })
  }

  /** P35-A: Take Survey——(可选带上 dontShowAgain)跳调查页 */
  private takeSurveyJtbd(): void {
    const dontShowAgain = this.jtbdCheckboxChecked
    this.jtbdPopupVisible = false
    if (dontShowAgain) {
      this.jtbdDontShow = true
      const ctx = getContext(this)
      JtbdStore.write(ctx, { 'dontShow': true } as Record<string, Object>)
    }
    console.info('[P35] jtbd Take Survey clicked, dontShowAgain=' + dontShowAgain)
    router.pushUrl({ url: 'pages/JtbdSurveyPage' })
  }

  aboutToDisappear(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
      console.info('AgentSidePanel settle polling stopped')
    }
    if (this.ctxPollTimer >= 0) {
      clearInterval(this.ctxPollTimer)
      this.ctxPollTimer = -1
      console.info('[P33] AgentSidePanel ctx polling stopped')
    }
    if (this.daTimer >= 0) {
      clearInterval(this.daTimer)
      this.daTimer = -1
      console.info('[P67] AgentSidePanel da polling stopped')
    }
  }

  /** P33-B: Preferences(chat_mode) 载入聊天模式,缺省 agent */
  private loadChatMode(): void {
    try {
      const ctx = getContext(this)
      preferences.getPreferences(ctx, 'sidepanel_prefs').then((p: preferences.Preferences) => {
        return p.get('chat_mode', 'agent')
      }).then((v: preferences.ValueType) => {
        const mode = `${v}`
        this.chatMode = mode === 'chat' ? 'chat' : 'agent'
        console.info('[P33] chat mode loaded: ' + this.chatMode)
      }).catch((e: BusinessError) => {
        console.warn('[P33] chat mode load error: ' + e.code)
      })
    } catch (e) {
      console.warn('[P33] chat mode getContext error: ' + e)
    }
  }

  /** P33-B: 切换 chat/agent 模式并持久化 */
  private toggleChatMode(): void {
    this.chatMode = this.chatMode === 'chat' ? 'agent' : 'chat'
    console.info('[P33] chat mode toggled: ' + this.chatMode)
    try {
      const ctx = getContext(this)
      preferences.getPreferences(ctx, 'sidepanel_prefs').then((p: preferences.Preferences) => {
        p.put('chat_mode', this.chatMode).then(() => {
          return p.flush()
        }).then(() => {
          console.info('[P33] chat mode saved: ' + this.chatMode)
        }).catch((e: BusinessError) => {
          console.warn('[P33] chat mode save error: ' + e.code)
        })
      })
    } catch (e) {
      console.warn('[P33] chat mode save exception: ' + e)
    }
  }

  /** P33-A/C: 1s 轮询——活动网页 tab 的选中文本 + 自动附加 tab */
  private startCtxPolling(): void {
    this.ctxPollTimer = setInterval(() => {
      this.pollContext()
    }, 1000)
  }

  /** 取活动非 dashboard tab 的 webview 实例(无则 null) */
  private activeWebTab(): AttachedTabInfo | null {
    const tabId = TabManager.getActiveTabId()
    if (tabId.length === 0) {
      return null
    }
    const tab = TabManager.getTab(tabId)
    if (tab === null || tab.isDashboard) {
      return null
    }
    const info = new AttachedTabInfo()
    info.tabId = tab.tabId
    info.title = tab.title.length > 0 ? tab.title : tab.currentUrl
    info.url = tab.currentUrl
    return info
  }

  private pollContext(): void {
    // C: 活动 tab 切换 → 解除"本次会话不再自动附加"抑制
    const activeTabId = TabManager.getActiveTabId()
    if (this.lastSeenActiveTabId.length > 0 && activeTabId !== this.lastSeenActiveTabId) {
      this.suppressAutoAttach = false
      console.info('[P33] active tab switched -> auto-attach re-enabled')
    }
    this.lastSeenActiveTabId = activeTabId
    // C: 自动附加(未抑制且当前无 chip 时)
    if (!this.suppressAutoAttach && this.attachedTab === null) {
      const t = this.activeWebTab()
      if (t !== null && t.url.length > 0) {
        this.attachedTab = t
        console.info('[P33] tab auto-attached: ' + t.title + ' (' + t.url + ')')
      }
    }
    // A: 选中文本轮询(仅 dashboard 无 web 时跳过)
    this.pollSelection()
  }

  private pollSelection(): void {
    const tabId = TabManager.getActiveTabId()
    const tab = TabManager.getTab(tabId)
    if (tab === null || tab.isDashboard) {
      return
    }
    const inst = TabManager.getWebView(tabId)
    if (inst === null || inst.controller === undefined) {
      return
    }
    inst.controller.runJavaScript(JSBridgeInjector.readSelection()).then((r: string) => {
      // runJavaScript 对字符串结果会再包一层 JSON 引号,先解包
      let raw = r
      try {
        raw = JSON.parse(r) as string
      } catch (e) {
        raw = r
      }
      if (raw === null || raw === 'null' || raw.length === 0) {
        if (this.pageSelection !== null) {
          this.pageSelection = null
        }
        return
      }
      try {
        const obj = JSON.parse(raw) as Record<string, Object>
        const sel = new PageSelection()
        sel.text = `${obj['text'] ?? ''}`
        sel.pageUrl = `${obj['pageUrl'] ?? ''}`
        sel.pageTitle = `${obj['pageTitle'] ?? ''}`
        sel.timestamp = obj['timestamp'] as number
        if (sel.text.length > 0 && this.pageSelection?.text !== sel.text) {
          this.pageSelection = sel
          console.info('[P33] selection captured: ' + sel.text.length + ' chars from ' + sel.pageUrl)
        }
      } catch (e) {
        // 静默:非预期格式
      }
    }).catch(() => {
      // webview 未就绪,静默
    })
  }

  /** P33: 拼接发送上下文(选中文本 + 附加 tab),含打点 */
  private buildContextBlock(): string {
    const parts: string[] = []
    if (this.pageSelection !== null && this.pageSelection.text.length > 0) {
      parts.push('用户在页面选中的文本(from ' + this.pageSelection.pageTitle + ' / ' + this.pageSelection.pageUrl + '):\n' + this.pageSelection.text)
    }
    if (this.attachedTab !== null) {
      parts.push('附加标签页: ' + this.attachedTab.title + ' (' + this.attachedTab.url + ')')
    }
    return parts.join('\n\n')
  }

  /** P33-B: chat 模式单轮 LLM 直答(无工具循环,不建 agent 卡不 glow) */
  private async sendChatSingleTurn(task: string): Promise<void> {
    const cfg = ConfigManager.get()
    if (cfg.llmBaseUrl.length === 0 || cfg.llmModel.length === 0) {
      this.messages.push({ role: 'hint', text: I18n.t('asLlmHint'), agentId: '' })
      return
    }
    const ctxBlock = this.buildContextBlock()
    let userContent = task
    if (ctxBlock.length > 0) {
      userContent = ctxBlock + '\n\n---\n\n用户问题: ' + task
    }
    const msgs: LLMChatMessage[] = [
      LLMChatMessage.system('你是浏览器内置的聊天助手(只读模式,不能操作页面)。基于用户提供的页面上下文简洁回答。'),
      LLMChatMessage.user(userContent)
    ]
    const opts: LLMRequestOptions = {
      baseUrl: cfg.llmBaseUrl,
      apiKey: cfg.llmApiKey,
      model: cfg.llmModel,
      messages: msgs,
      tools: [],
      timeoutMs: 60000
    }
    console.info('[P33] chat single-turn start: task="' + task.substring(0, 80) + '" ctxLen=' + ctxBlock.length)
    this.chatBusy = true
    try {
      const resp = await LLMClient.chat(opts)
      if (resp !== null && resp.content.length > 0) {
        this.messages.push({ role: 'agent', text: resp.content, agentId: '' })
        console.info('[P33] chat single-turn answer: ' + resp.content.length + ' chars')
      } else {
        const reason = LLMClient.lastError.length > 0 ? LLMClient.lastError : I18n.t('asLlmNoResp')
        this.messages.push({ role: 'hint', text: I18n.t('asChatFail') + reason, agentId: '' })
        console.warn('[P33] chat single-turn failed: ' + reason)
      }
    } catch (e) {
      this.messages.push({ role: 'hint', text: I18n.t('asChatError') + e, agentId: '' })
      console.warn('[P33] chat single-turn exception: ' + e)
    } finally {
      this.chatBusy = false
      // P35-A: chat 单轮消息同样计入 jtbd 阈值（与 agent 回流路径同款触发）
      this.maybeFireJtbdPopup()
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Bottom)
      }, 50)
    }
  }

  /** P19a: 轮询本面板派发过的 agent 终态，答案/失败原因回流成气泡 */
  private startSettlePolling(): void {
    this.pollTimer = setInterval(() => {
      this.pollSettled()
    }, 1000)
  }

  private pollSettled(): void {
    let changed = false
    for (const msg of this.messages) {
      if (msg.agentId.length > 0) {
        this.settledAgents.add(msg.agentId)
      }
    }
    for (const st of this.agents) {
      const id = st.agentId
      if (this.settledAgents.has(id)) {
        continue
      }
      if (st.status === AgentStatus.COMPLETED) {
        const ans = AgentEngine.getFinalAnswer(id)
        const text = ans !== null ? (ans.length > 500 ? ans.substring(0, 500) + '…' : ans) : I18n.t('asDone')
        this.messages.push({ role: 'agent', text: text, agentId: id })
        this.settledAgents.add(id)
        changed = true
        console.info('AgentSidePanel answer reflux agent=' + id + ' len=' + text.length)
      } else if (st.status === AgentStatus.ERROR || st.status === AgentStatus.STOPPED) {
        const reason = st.errorMessage.length > 0 ? st.errorMessage : (AgentEngine.getFinalAnswer(id) ?? I18n.t('asTerminated'))
        this.messages.push({ role: 'hint', text: '⚠ ' + reason, agentId: id })
        this.settledAgents.add(id)
        changed = true
        console.info('AgentSidePanel fail reflux agent=' + id + ' reason=' + reason)
      }
    }
    if (changed) {
      this.agents = AgentEngine.getAllAgentStatus()
      this.maybeFireJtbdPopup()
      // 新气泡推入后滚到底部（下一帧执行，确保布局已更新）
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Bottom)
      }, 50)
    }
  }

  /** P24b: Preferences 加载 starter_prompts(JSON 数组3元素 {display,prompt}, 解析失败回默认) */
  private loadStarterPrompts(): void {
    try {
      const ctx = getContext(this)
      preferences.getPreferences(ctx, 'sidepanel_prefs').then((p: preferences.Preferences) => {
        return p.get('starter_prompts', '')
      }).then((v: preferences.ValueType) => {
        const raw = `${v}`
        if (raw.length > 0) {
          try {
            const arr = JSON.parse(raw) as Array<Record<string, string>>
            if (arr !== null && arr !== undefined && arr.length === 3) {
              const loaded: StarterPrompt[] = []
              for (const it of arr) {
                loaded.push(new StarterPrompt(it.display ?? '', it.prompt ?? ''))
              }
              this.starters = loaded
              console.info('AgentSidePanel starter prompts loaded from Preferences')
              return
            }
          } catch (e) {
            console.warn('AgentSidePanel starter prompts parse failed, fallback to defaults')
          }
        }
        this.starters = defaultStarterPrompts()
      }).catch((e: BusinessError) => {
        console.warn('AgentSidePanel starter prompts load error: ' + e.code)
      })
    } catch (e) {
      console.warn('AgentSidePanel starter prompts getContext error: ' + e)
    }
  }

  /** P24b: 保存自定义起手词到 Preferences */
  private saveStarterPrompts(list: StarterPrompt[]): void {
    try {
      const ctx = getContext(this)
      const arr: Array<Record<string, string>> = []
      for (const s of list) {
        const m: Record<string, string> = {}
        m['display'] = s.display
        m['prompt'] = s.prompt
        arr.push(m)
      }
      const raw = JSON.stringify(arr)
      preferences.getPreferences(ctx, 'sidepanel_prefs').then((p: preferences.Preferences) => {
        p.put('starter_prompts', raw).then(() => {
          return p.flush()
        }).then(() => {
          console.info('AgentSidePanel starter prompts saved')
        }).catch((e: BusinessError) => {
          console.warn('AgentSidePanel starter prompts save error: ' + e.code)
        })
      })
    } catch (e) {
      console.warn('AgentSidePanel starter prompts save exception: ' + e)
    }
  }

  /** P24b: 打开内联编辑器(预填当前值) */
  private openStarterEditor(): void {
    this.edDisplay0 = this.starters[0].display
    this.edPrompt0 = this.starters[0].prompt
    this.edDisplay1 = this.starters[1].display
    this.edPrompt1 = this.starters[1].prompt
    this.edDisplay2 = this.starters[2].display
    this.edPrompt2 = this.starters[2].prompt
    this.editingStarters = true
  }

  /** P24b: 保存编辑(空 prompt 行忽略→回默认该行) */
  private applyStarterEdits(): void {
    const d0 = this.edDisplay0.trim().length > 0 ? this.edDisplay0.trim() : I18n.t('asPromptN') + '1'
    const p0 = this.edPrompt0.trim().length > 0 ? this.edPrompt0.trim() : defaultStarterPrompts()[0].prompt
    const d1 = this.edDisplay1.trim().length > 0 ? this.edDisplay1.trim() : I18n.t('asPromptN') + '2'
    const p1 = this.edPrompt1.trim().length > 0 ? this.edPrompt1.trim() : defaultStarterPrompts()[1].prompt
    const d2 = this.edDisplay2.trim().length > 0 ? this.edDisplay2.trim() : I18n.t('asPromptN') + '3'
    const p2 = this.edPrompt2.trim().length > 0 ? this.edPrompt2.trim() : defaultStarterPrompts()[2].prompt
    const list: StarterPrompt[] = [new StarterPrompt(d0, p0), new StarterPrompt(d1, p1), new StarterPrompt(d2, p2)]
    this.starters = list
    this.saveStarterPrompts(list)
    this.editingStarters = false
  }

  /** P24b: 点起手按钮 = 以 prompt 作为任务文本直接发送 */
  private sendStarter(s: StarterPrompt): void {
    this.inputText = s.prompt
    this.sendTask()
  }

  /** P24c: 是否有本面板派发且仍在运行的 agent */
  private hasRunningAgent(): boolean {
    this.agents = AgentEngine.getAllAgentStatus()
    for (const st of this.agents) {
      if (st.status === AgentStatus.RUNNING) {
        this.lastRunningAgentId = st.agentId
        return true
      }
    }
    this.lastRunningAgentId = ''
    return false
  }

  /** P24c: 停止最近运行的 agent */
  private stopRunningAgent(): void {
    if (this.lastRunningAgentId.length === 0) {
      this.hasRunningAgent()
    }
    if (this.lastRunningAgentId.length > 0) {
      console.info('AgentSidePanel stop agent: ' + this.lastRunningAgentId)
      AgentEngine.terminateAgent(this.lastRunningAgentId)
      this.lastRunningAgentId = ''
    }
  }

  private sendTask(): void {
    const task = this.inputText.trim()
    if (task.length === 0) {
      return
    }
    // P67: 选中设备智能体 → 收件箱模式（优先于 chat/agent 模式）
    if (this.daSel.length > 0) {
      this.messages.push({ role: 'user', text: task, agentId: '' })
      this.dispatchDaTask(task, this.buildContextBlock())
      this.inputText = ''
      return
    }
    // P33-B: chat 模式 = 单轮 LLM 直答,不走 createAgent 工具循环
    if (this.chatMode === 'chat') {
      this.messages.push({ role: 'user', text: task, agentId: '' })
      this.inputText = ''
      this.sendChatSingleTurn(task)
      return
    }
    // ref1 模式：侧栏任务驱动活动 tab — 无目标 URL 时用配置端点页兜底
    const cfg = ConfigManager.get()
    const targetUrl = cfg.llmBaseUrl.length > 0 ? cfg.llmBaseUrl : 'https://example.com'
    // P33-A/C: 上下文注入 agent 任务描述(选中文本 + 附加 tab)
    const ctxBlock = this.buildContextBlock()
    const fullTask = ctxBlock.length > 0 ? task + '\n\n[附加上下文]\n' + ctxBlock : task
    this.messages.push({ role: 'user', text: task, agentId: '' })
    const agent = AgentEngine.createAgent('sidepanel', targetUrl, fullTask, RunStrategy.ONCE)
    if (agent) {
      this.messages.push({
        role: 'hint',
        text: I18n.t('asStarted') + agent.agentId.substring(0, 12) + I18n.t('asStartedEnd'),
        agentId: agent.agentId
      })
      this.agents = AgentEngine.getAllAgentStatus()
      this.lastRunningAgentId = agent.agentId
      this.inputText = ''
      if (ctxBlock.length > 0) {
        console.info('[P33] agent task with context: sel=' + (this.pageSelection !== null ? this.pageSelection.text.length : 0) + ' chars, attachedTab=' + (this.attachedTab !== null ? this.attachedTab.title : 'none'))
      }
      console.info('AgentSidePanel task dispatched: ' + task + ' agent=' + agent.agentId)
    } else {
      this.messages.push({ role: 'hint', text: I18n.t('asCreateFail'), agentId: '' })
      console.warn('AgentSidePanel createAgent returned null')
    }
    // P33-A: 发送后清空选中文本 chip(已消费)
    this.pageSelection = null
  }

  /** P21b: 切到 history 视图并拉取会话列表(每次进入拉一次,数据量小不做下拉) */
  private switchToHistory(): void {
    this.panelView = 'history'
    this.refreshHistory()
  }

  /** P21b: 拉取会话列表(活跃内存 + 磁盘历史,startTime 降序) */
  private async refreshHistory(): Promise<void> {
    this.historyLoading = true
    try {
      const list = await SessionManager.getSessionListAsync()
      this.historySessions = list
      console.info('AgentSidePanel history loaded: ' + list.length + ' sessions')
    } catch (e) {
      console.warn('AgentSidePanel history load failed: ' + e)
    } finally {
      this.historyLoading = false
    }
  }

  /** P21b: 任务描述行——优先 agent 配置的 taskDescription,无则回退 URL 序列或 agentId */
  private sessionLabel(s: SessionRecord): string {
    const cfg = AgentEngine.getAgentConfig(s.agentId)
    if (cfg && cfg.taskDescription.length > 0) {
      return cfg.taskDescription
    }
    if (s.urlSequence.length > 0 && s.urlSequence[0].length > 0) {
      return s.urlSequence[0]
    }
    return s.agentId.length > 0 ? s.agentId : s.sessionId
  }

  /** P21b: 会话时间描述(上游 dayjs.fromNow 风格:今天 HH:mm / 昨天 / MM-DD / YYYY-MM-DD) */
  private sessionTimeLabel(t: number): string {
    if (t <= 0) {
      return ''
    }
    const d = new Date(t)
    const now = new Date()
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n)
    const sameDay = (a: Date, b: Date): boolean =>
      a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
    if (sameDay(d, now)) {
      return `${I18n.t('ntToday')} ${pad(d.getHours())}:${pad(d.getMinutes())}`
    }
    if (sameDay(d, yesterday)) {
      return `${I18n.t('ntYesterday')} ${pad(d.getHours())}:${pad(d.getMinutes())}`
    }
    if (d.getFullYear() === now.getFullYear()) {
      return `${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    }
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  }

  /** P21b: 点历史行 → 回放页 */
  private openSession(s: SessionRecord): void {
    console.info('AgentSidePanel open session replay: ' + s.sessionId)
    router.pushUrl({ url: 'pages/SessionPlayerPage', params: { sessionId: s.sessionId } })
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('AgentSidePanel theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Column() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // P51-C: localeVersion anchor
        if (this.localeVersion < 0) {
          Text('').fontSize(0)
        }

      // 顶部标题栏（对齐上游 ChatHeader：左 Agent 标题+视图切换，右 模型下拉+⚙+关闭）
      Row() {
        Text('Agent')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)

        // 视图切换（上游：非 history 页显示 History 图标钮；history 页换成 Plus 回到新会话）
        if (this.panelView === 'chat') {
          Image($rawfile('ic_history.svg'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
            .width(28)
            .accessibilityText(I18n.t('asViewHistory'))
            .onClick(() => {
              this.switchToHistory()
            })
        } else {
          Image($rawfile('ic_add.svg'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
            .width(28)
            .accessibilityText(I18n.t('asNewChat'))
            .onClick(() => {
              this.panelView = 'chat'
            })
        }

        Blank()

        // P67: 模型/智能体真下拉（LLM providers + 设备智能体两段式）
        Column() {
          Row() {
            Text(this.daSel.length > 0 ? ('🤖 ' + this.daSel)
              : (this.modelOptions()[this.modelSelection] || this.modelOptions()[0]))
              .fontSize(11)
              .fontColor('#1A73E8')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 100 })
            Image($rawfile('ic_arrow_down.svg'))
              .width(10).height(10)
              .fillColor(this.pal().text2)
              .draggable(false)
              .margin({ left: 4 })
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(this.pal().selected)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.daModelOpen = !this.daModelOpen
            console.info('[P67] sidepanel model dropdown: ' + this.daModelOpen)
          })

          if (this.daModelOpen) {
            Column() {
              // 段1：LLM 提供商/模型（内置循环切换语义保留：点击循环 +1）
              Text(this.modelOptions()[this.modelSelection])
                .fontSize(11)
                .fontColor(this.pal().text)
                .maxLines(1)
                .width('100%')
                .textAlign(TextAlign.Start)
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .borderRadius(8)
                .backgroundColor(this.pal().surface)
                .onClick(() => {
                  this.modelSelection = (this.modelSelection + 1) % this.modelOptions().length
                  if (this.modelOptions()[this.modelSelection] === I18n.t('asManageProviders')) {
                    // p23b: 循环到管理项 = 跳 LLM Hub，选择回退保持原模型显示
                    router.pushUrl({ url: 'pages/LlmHubPage' })
                    this.modelSelection = 0
                    return
                  }
                  this.daSel = ''
                  console.info('AgentSidePanel model switch: ' + this.modelOptions()[this.modelSelection])
                })
              // 段2：设备智能体（注册表，在线点）
              Text(I18n.t('daDeviceAgents'))
                .fontSize(9)
                .fontColor(this.pal().text2)
                .width('100%')
                .textAlign(TextAlign.Start)
                .margin({ top: 6, bottom: 2 })
              if (this.daAgents.length === 0) {
                Text(I18n.t('daNoAgents'))
                  .fontSize(9)
                  .fontColor(this.pal().text2)
                  .maxLines(2)
                  .width('100%')
                  .textAlign(TextAlign.Start)
              } else {
                ForEach(this.daAgents, (a: DeviceAgentEntry) => {
                  Row() {
                    Circle()
                    .width(6)
                    .height(6)
                    .fill(DeviceAgentStore.isOnline(a) ? '#22C55E' : '#9AA0A6')
                    .margin({ right: 6 })
                    Text(a.name)
                      .fontSize(11)
                      .fontColor(this.pal().text)
                      .maxLines(1)
                      .layoutWeight(1)
                    if (this.daSel === a.name) {
                      Image($rawfile('ic_check.svg'))
                        .width(12).height(12)
                        .fillColor('#22C55E')
                        .draggable(false)
                    }
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                  .borderRadius(8)
                  .backgroundColor(this.pal().surface)
                  .alignItems(VerticalAlign.Center)
                  .onClick(() => {
                    this.daSel = this.daSel === a.name ? '' : a.name
                    this.daModelOpen = false
                    console.info('[P67] sidepanel da selected: ' + this.daSel)
                  })
                }, (a: DeviceAgentEntry) => 'sda_' + a.name + '_' + a.lastSeen)
              }
            }
            .width('100%')
            .padding(6)
            .borderRadius(10)
            .backgroundColor(this.pal().surface)
            .border({ width: 1, color: this.pal().border })
            .margin({ top: 6 })
          }
        }

        Image($rawfile('ic_settings.svg'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(28)

        Image($rawfile('ic_close.svg'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(28)
          .accessibilityText(I18n.t('asClosePanel'))
          .onClick(() => {
            this.onClose()
          })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 8 })
      .backgroundColor(this.pal().surfaceAlt)
      .border({ width: { bottom: 1 }, color: this.pal().border })

      // 主体：chat 视图（消息列表 + 输入区） / history 视图（会话历史列表,上游 ChatHistory）
      if (this.panelView === 'chat') {
        // P24b: 空态 = 起手提示词面板(对标 ChatEmptyState: 图标+标题+3按钮+自定义入口)
        if (this.messages.length <= 1 && !this.editingStarters) {
          Column() {
            Image($rawfile('ic_agent.svg'))
              .width(44)
              .height(44)
              .fillColor('#FB6618')
              .draggable(false)
              .margin({ top: 36 })
            Text(I18n.t('asReady'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().text)
              .margin({ top: 12 })
            Text(I18n.t('asReadyDesc'))
              .fontSize(11)
              .fontColor(this.pal().text2)
              .margin({ top: 4 })
            Column() {
              ForEach(this.starters, (s: StarterPrompt) => {
                Text(s.display)
                  .fontSize(13)
                  .fontColor(this.pal().text)
                  .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                  .borderRadius(10)
                  .backgroundColor(this.pal().surface)
                  .border({ width: 1, color: this.pal().border })
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .margin({ top: 8 })
                  .onClick(() => {
                    this.sendStarter(s)
                  })
              }, (s: StarterPrompt, idx: number) => 'starter_' + idx)
            }
            .width('100%')
            .constraintSize({ maxWidth: 320 })
            .margin({ top: 16 })
            Text(I18n.t('asCustomPrompts'))
              .fontSize(11)
              .fontColor('#FB6618')
              .margin({ top: 14 })
              .onClick(() => {
                this.openStarterEditor()
              })
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.pal().surfaceAlt)
        } else if (this.editingStarters) {
          // P24b: 内联编辑器(3 对 display+prompt 输入 + 保存/取消)
          Scroll() {
            Column() {
              Text(I18n.t('asCustomPromptsTitle'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal().text)
                .margin({ top: 16 })
              Text(I18n.t('asCustomPromptsHint'))
                .fontSize(10)
                .fontColor(this.pal().text2)
                .margin({ top: 4, bottom: 8 })
              ForEach([0, 1, 2], (idx: number) => {
                Column() {
                  TextInput({ text: idx === 0 ? this.edDisplay0 : idx === 1 ? this.edDisplay1 : this.edDisplay2, placeholder: I18n.t('asBtnLabel') + (idx + 1) })
                    .fontSize(12)
                    .height(36)
                    .backgroundColor(this.pal().surface)
                    .borderRadius(8)
                    .onChange((v: string) => {
                      if (idx === 0) { this.edDisplay0 = v } else if (idx === 1) { this.edDisplay1 = v } else { this.edDisplay2 = v }
                    })
                  TextArea({ text: idx === 0 ? this.edPrompt0 : idx === 1 ? this.edPrompt1 : this.edPrompt2, placeholder: I18n.t('asCmdLabel') + (idx + 1) })
                    .fontSize(12)
                    .height(56)
                    .backgroundColor(this.pal().surface)
                    .borderRadius(8)
                    .margin({ top: 6 })
                    .onChange((v: string) => {
                      if (idx === 0) { this.edPrompt0 = v } else if (idx === 1) { this.edPrompt1 = v } else { this.edPrompt2 = v }
                    })
                }
                .width('100%')
                .margin({ top: 10 })
              }, (idx: number) => 'ed_' + idx)
              Row() {
                Button(I18n.t('cancel'))
                  .fontSize(12)
                  .height(32)
                  .backgroundColor(this.pal().surface)
                  .fontColor(this.pal().text2)
                  .borderRadius(16)
                  .border({ width: 1, color: this.pal().border })
                  .onClick(() => {
                    this.editingStarters = false
                  })
                Blank()
                Button(I18n.t('save'))
                  .fontSize(12)
                  .height(32)
                  .backgroundColor('#FB6618')
                  .fontColor('#FFFFFF')
                  .borderRadius(16)
                  .onClick(() => {
                    this.applyStarterEdits()
                  })
              }
              .width('100%')
              .margin({ top: 16, bottom: 20 })
            }
            .width('100%')
            .constraintSize({ maxWidth: 320 })
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .backgroundColor(this.pal().surfaceAlt)
        } else {
        // 消息列表
        List({ scroller: this.scroller }) {
          ForEach(this.messages, (msg: ChatMessage, index: number) => {
            ListItem() {
              if (msg.role === 'user') {
                // 用户右气泡
                Row() {
                  Blank()
                  Text(msg.text)
                    .fontSize(13)
                    .fontColor('#FFFFFF')
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .borderRadius(12)
                    .backgroundColor('#1A73E8')
                    .constraintSize({ maxWidth: 260 })
                }
                .width('100%')
              } else {
                // 助手/系统左卡(P21b: surface 卡片,与 surfaceAlt 面板底区分)
                Row() {
                  Text(msg.text)
                    .fontSize(12)
                    .fontColor(this.pal().text2)
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .borderRadius(12)
                    .backgroundColor(this.pal().surface)
                    .constraintSize({ maxWidth: 260 })
                }
                .width('100%')
              }
            }
            .padding({ top: 4, bottom: 4 })
          }, (msg: ChatMessage, index: number) => index + '_' + msg.text)
          // P35-A: jtbd 调查弹窗（对标上游 JtbdPopup: assistant 消息内卡片）
          if (this.jtbdPopupVisible) {
            ListItem() {
              Column() {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Row() {
                    Image($rawfile('ic_sparkles.svg'))
                      .width(18).height(18)
                      .fillColor('#F0983F')
                      .draggable(false)
                      .margin({ right: 10, top: 2 })
                    Column() {
                      Text('Help us improve BrowserOS!')
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.pal().text)
                      Text('Take a quick 3-minute survey.')
                        .fontSize(11)
                        .fontColor(this.pal().text2)
                        .margin({ top: 4 })
                    }
                    .alignItems(HorizontalAlign.Start)
                  }
                  .alignItems(VerticalAlign.Top)
                  .padding({ right: 24 })

                  Image($rawfile('ic_close.svg'))
                    .width(13).height(13)
                    .fillColor(this.pal().text2)
                    .draggable(false)
                    .accessibilityText(I18n.t('asCloseSurvey'))
                    .onClick(() => {
                      this.dismissJtbd(this.jtbdCheckboxChecked)
                    })
                }
                .width('100%')

                // shownCount≥2 起显示「不再显示」复选框（上游 DONT_SHOW_AGAIN_AFTER=2）
                if (this.jtbdShownCount >= this.JTBD_DONT_SHOW_AFTER) {
                  Row() {
                    Checkbox()
                      .select(this.jtbdCheckboxChecked)
                      .selectedColor('#F0983F')
                      .width(16)
                      .height(16)
                      .onChange((v: boolean) => {
                        this.jtbdCheckboxChecked = v
                      })
                    Text(I18n.t('asNoSurvey'))
                      .fontSize(11)
                      .fontColor(this.pal().text2)
                      .margin({ left: 6 })
                  }
                  .margin({ top: 10 })
                  .alignItems(VerticalAlign.Center)
                }

                Row() {
                  Button('Take Survey')
                    .fontSize(12)
                    .height(30)
                    .padding({ left: 14, right: 14 })
                    .backgroundColor('#F0983F')
                    .fontColor('#FFFFFF')
                    .borderRadius(15)
                    .onClick(() => {
                      this.takeSurveyJtbd()
                    })
                  Button('Maybe Later')
                    .fontSize(12)
                    .height(30)
                    .padding({ left: 14, right: 14 })
                    .backgroundColor(this.pal().surfaceAlt)
                    .fontColor(this.pal().text2)
                    .borderRadius(15)
                    .border({ width: 1, color: this.pal().border })
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.dismissJtbd(this.jtbdCheckboxChecked)
                    })
                }
                .margin({ top: 12 })
              }
              .padding(14)
              .borderRadius(12)
              .backgroundColor(this.pal().surface)
              .border({ width: 1, color: this.pal().border })
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 12, right: 12 })
        .scrollBar(BarState.Off)
        // P21b: chat 内容区与面板底同色(surfaceAlt), 气泡用 surface 卡片区分
        .backgroundColor(this.pal().surfaceAlt)
        }

        // 底部输入区
        Column() {
          // P33-B: 模式切换 pill(对标上游 ChatModeToggle, 点击切换 chat/agent)
          Row() {
            if (this.chatMode === 'chat') {
              Row() {
                Image($rawfile('ic_tab_search.svg'))
                  .width(13).height(13)
                  .fillColor('#F28B82')
                  .draggable(false)
                  .margin({ right: 5 })
                Text('Chat Mode ON')
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#F28B82')
                Text(I18n.t('asReadOnly'))
                  .fontSize(9)
                  .fontColor('#F28B82')
                  .opacity(0.8)
              }
              .height(26)
              .padding({ left: 10, right: 10 })
              .borderRadius(13)
              .border({ width: 1, color: '#F28B82' })
              .backgroundColor('#33F28B82')
              .alignItems(VerticalAlign.Center)
              .accessibilityText(I18n.t('asChatMode'))
              .onClick(() => {
                this.toggleChatMode()
              })
            } else {
              Row() {
                Image($rawfile('ic_robot.svg'))
                  .width(13).height(13)
                  .fillColor(this.pal().text2)
                  .draggable(false)
                  .margin({ right: 5 })
                Text('Agent Mode ON')
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.pal().text2)
              }
              .height(26)
              .padding({ left: 10, right: 10 })
              .borderRadius(13)
              .border({ width: 1, color: this.pal().border })
              .backgroundColor(this.pal().surfaceAlt)
              .alignItems(VerticalAlign.Center)
              .accessibilityText(I18n.t('asAgentMode'))
              .onClick(() => {
                this.toggleChatMode()
              })
            }
            Blank()
          }
          .width('100%')
          .margin({ bottom: 6 })

          // P33-A: 选中文本 chip(对标上游 selectedTextStorage 提示)
          if (this.pageSelection !== null) {
            Row() {
              Text(I18n.t('asSelectedN') + this.pageSelection.text.length + I18n.t('asChars'))
                .fontSize(10)
                .fontColor(this.pal().text2)
                .maxLines(1)
                .constraintSize({ maxWidth: 180 })
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Image($rawfile('ic_close.svg'))
                .width(11).height(11)
                .fillColor(this.pal().text2)
                .draggable(false)
                .margin({ left: 6 })
                .accessibilityText(I18n.t('asDiscardSel'))
                .onClick(() => {
                  this.pageSelection = null
                  console.info('[P33] selection chip dismissed')
                })
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(10)
            .backgroundColor(this.pal().surfaceAlt)
            .border({ width: 1, color: this.pal().border })
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: 6 })
          }

          // P33-C: 附加标签页 chip(对标上游 ChatAttachedTabs)
          if (this.attachedTab !== null) {
            Row() {
              Image($rawfile('ic_public.svg'))
                .width(12).height(12)
                .fillColor(this.pal().text2)
                .draggable(false)
                .margin({ right: 5 })
              Text(this.attachedTab.title)
                .fontSize(10)
                .fontColor(this.pal().text2)
                .maxLines(1)
                .constraintSize({ maxWidth: 170 })
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Image($rawfile('ic_close.svg'))
                .width(11).height(11)
                .fillColor(this.pal().text2)
                .draggable(false)
                .margin({ left: 6 })
                .accessibilityText(I18n.t('asRemoveTab'))
                .onClick(() => {
                  this.attachedTab = null
                  this.suppressAutoAttach = true
                  console.info('[P33] attached tab removed, auto-attach suppressed until tab switch')
                })
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(10)
            .backgroundColor(this.pal().surfaceAlt)
            .border({ width: 1, color: this.pal().border })
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: 6 })
          }

          TextArea({ text: this.inputText, placeholder: I18n.t('asInputPh') })
            .width('100%')
            .height(72)
            .fontSize(13)
            .backgroundColor(this.pal().surfaceAlt)
            .borderRadius(10)
            .onChange((v: string) => {
              this.inputText = v
            })
          Row() {
            Text(`${this.agents.length}${I18n.t('asAgentsRunning')}`)
              .fontSize(10)
              .fontColor('#9AA0A6')
              .layoutWeight(1)
            if (this.hasRunningAgent()) {
              // P24c: 运行中 = 红底停止钮(对标 chat-actions stop)
              Row() {
                Image($rawfile('ic_stop.svg'))
                  .width(14)
                  .height(14)
                  .fillColor('#FFFFFF')
                  .draggable(false)
                  .margin({ right: 6 })
                Text(I18n.t('asStop'))
                  .fontSize(13)
                  .fontColor('#FFFFFF')
              }
              .height(32)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#DC2626')
              .borderRadius(16)
              .onClick(() => {
                this.stopRunningAgent()
              })
            } else {
              Button(I18n.t('tbSend'))
                .fontSize(13)
                .height(32)
                .backgroundColor('#1A73E8')
                .fontColor('#FFFFFF')
                .borderRadius(16)
                .onClick(() => {
                  this.sendTask()
                })
            }
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .padding({ top: 8, bottom: 10 })
        .backgroundColor(this.pal().surface)
        .border({ width: { top: 1 }, color: this.pal().border })
      } else {
        // ===== history 视图（上游 ChatHistory：时间分组会话列表 + 空态引导）=====
        if (this.historyLoading && this.historySessions.length === 0) {
          Column() {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(this.pal().text2)
            Text(I18n.t('asFetching'))
              .fontSize(12)
              .fontColor(this.pal().text2)
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.historySessions.length === 0) {
          // 空态（上游：MessageSquare 图标 + emptyMessage + "Start a new chat" 链接）
          Column() {
            Image($rawfile('ic_robot.svg'))
              .width(40)
              .height(40)
              .fillColor(this.pal().text2)
              .opacity(0.5)
              .draggable(false)
            Text(I18n.t('asNoHistory'))
              .fontSize(14)
              .fontColor(this.pal().text2)
              .margin({ top: 12 })
            Text(I18n.t('asNewSession'))
              .fontSize(13)
              .fontColor('#1A73E8')
              .margin({ top: 8 })
              .onClick(() => {
                this.panelView = 'chat'
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.historySessions, (s: SessionRecord) => {
              ListItem() {
                Row() {
                  Image($rawfile('ic_robot.svg'))
                    .width(18).height(18)
                    .fillColor(this.pal().text2)
                    .draggable(false)
                    .margin({ right: 10 })
                  Column() {
                    Text(this.sessionLabel(s))
                      .fontSize(13)
                      .fontColor(this.pal().text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.sessionTimeLabel(s.startTime) + ' · ' + s.operationLogs.length + I18n.t('asSteps'))
                      .fontSize(10)
                      .fontColor(this.pal().text2)
                      .margin({ top: 2 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(8)
                .onClick(() => {
                  this.openSession(s)
                })
              }
            }, (s: SessionRecord) => s.sessionId)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 8, right: 8, top: 4 })
          .scrollBar(BarState.Off)
          .divider({
            strokeWidth: 1,
            color: this.pal().border,
            startMargin: 40,
            endMargin: 0
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    // P21b: 面板底色与浏览器 chrome 区分——surfaceAlt(内容区同色),左侧细分隔线对齐上游风格
    .backgroundColor(this.pal().surfaceAlt)
  }
}
