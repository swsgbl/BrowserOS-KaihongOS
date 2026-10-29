import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { StorageManager } from '../storage/StorageManager'
import { ConfigManager } from '../storage/ConfigManager'
import { SecureStorageAdapter } from '../storage/SecureStorageAdapter'
import { AppConfig } from '../model/AppConfig'
import { MCPServer } from '../service/MCPServer'
import { HistoryManager } from '../service/HistoryManager'
import { LoginStateManager } from '../service/LoginStateManager'
import { SessionManager } from '../service/SessionManager'
import { DownloadManager } from '../service/DownloadManager'
import { TabManager } from '../service/TabManager'
import { TabGroupManager } from '../service/TabGroupManager'
import { ConnectionManager } from '../service/ConnectionManager'
import { ScheduleManager } from '../service/ScheduleManager'
import { JSBridgeInjector } from '../protocol/JSBridgeInjector'
import { I18n } from '../common/I18n'
import { UpdateService, UpdateSourcePref } from '../service/UpdateService'

export default class EntryAbility extends UIAbility {
  /** P36-B: 冷启动计时锚点（onCreate 首行），BrowserShell aboutToAppear 收口算 cold_start_ms */
  static readonly coldStartT0: number = Date.now()

  /** P36-fix: ConfigManager.load() 的 promise（入口页判定前必须 await） */
  private configReady: Promise<AppConfig> | null = null

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('BrowserOS KaihongOS EntryAbility onCreate')
    // P42 (KAI-079): html2canvas 本地源码预加载（rawfile → 内存缓存，截图断网可用）
    JSBridgeInjector.preloadHtml2Canvas(this.context.resourceManager)
    // 初始化链：存储基路径指向应用沙箱 filesDir → 加载配置
    // （DocManagementInitializer 保持不调用：该模块与本体无关）
    try {
      StorageManager.setBasePath(this.context.filesDir)
      console.info('EntryAbility StorageManager base path set: ' + this.context.filesDir)
    } catch (e) {
      console.error('EntryAbility setBasePath error: ' + e)
    }
    // P14a: 历史持久化装载链（RDB 建表 → 旧 JSON 一次性迁移 → 镜像装载 → 异步清理策略）
    HistoryManager.loadHistory(this.context).then(() => {
      console.info('EntryAbility HistoryManager loadHistory done')
    }).catch((e: BusinessError) => {
      console.error('EntryAbility HistoryManager loadHistory error: ' + e.message)
    })
    // P14b: 登录态 Preferences 载体初始化 + 装载（含旧 login_state/*.json 一次性迁移）
    LoginStateManager.init(this.context)
    LoginStateManager.loadPersistedStates().then(() => {
      console.info('EntryAbility LoginStateManager loadPersistedStates done, domains=' + LoginStateManager.getImportedDomains().length)
    }).catch((e: BusinessError) => {
      console.error('EntryAbility LoginStateManager loadPersistedStates error: ' + e.message)
    })
    // P14c 收尾: 会话元数据索引对账上移到启动（此前惰性——打开历史页才触发）
    SessionManager.ensurePersistedSessions().then(() => {
      console.info('EntryAbility session index reconciled: ' + SessionManager.getSessionList().length)
    }).catch((e: BusinessError) => {
      console.error('EntryAbility session reconcile error: ' + e.message)
    })
    // P48: i18n 初始化（读持久化 locale；完成前 t() 返回默认 zh）
    I18n.init(this.context).then(() => {
      console.info('EntryAbility I18n ready locale=' + I18n.getLocale() + ' bundle=' + I18n.getBundleSize())
    }).catch((e: BusinessError) => {
      console.error('EntryAbility I18n init error: ' + e.message)
    })
    // P36: 配置装载链 —— asset 探活(计时) → config.json 读取 → 明文密钥一次性迁移 asset → asset 真值回灌
    const p36T0 = Date.now()
    // P36-fix: 持有 load promise，onWindowStageCreate 的入口页判定必须等它完成
    // （asset 探测是真实异步 IPC，冷启 ~1.3s；不等会读到默认配置误入 OnboardingPage）
    this.configReady = ConfigManager.load().then((config) => {
      console.info(`EntryAbility ConfigManager loaded, mcpPort=${config.mcpPort} [P36] secure=${SecureStorageAdapter.isSecureStorageAvailable()} load_ms=${Date.now() - p36T0}`)
      // P3: 启动 MCP 网络层（HTTP transport 监听 127.0.0.1:{mcpPort}，token 每次启动新生成）
      const token = MCPServer.generateAuthToken()
      MCPServer.start(config.mcpPort, token, config.wsPort).then((ok) => {
        if (ok) {
          console.info('EntryAbility MCPServer started on port ' + config.mcpPort)
        } else {
          console.error('EntryAbility MCPServer start FAILED on port ' + config.mcpPort)
        }
      }).catch((e: BusinessError) => {
        console.error('EntryAbility MCPServer start error: ' + e.code + '/' + e.message)
      })
      // P69: 应用内更新 —— 服务初始化（读节流状态）+ 24h 节流自动查（失败静默）
      try {
        const usp = config.updateSourcePref
        UpdateService.init(this.context.filesDir, usp === 'cn' || usp === 'global' ? usp as UpdateSourcePref : 'auto')
        UpdateService.autoCheck()
      } catch (e69) {
        console.error('EntryAbility UpdateService init error: ' + e69)
      }
      return config
    }).catch((e: BusinessError) => {
      console.error('EntryAbility ConfigManager load error: ' + e.message)
      return ConfigManager.get()
    })
    // P23a: 定时任务调度器（config 就绪后启动 1 分钟 tick）
    ScheduleManager.init().catch((e: BusinessError) => {
      console.error('EntryAbility ScheduleManager init error: ' + e.message)
    })
    // P33-D: 更新日志通知由 ChangelogOverlay 组件自治(BrowserShell 根 Stack 常驻):
    // 版本比对+5s 延迟+落盘标记全在组件内完成(EntryAbility 侧 AppStorage 写入
    // 实测无法驱动页面 @StorageProp 刷新,故不在此触发)
  }

  onDestroy(): void {
    console.info('BrowserOS KaihongOS EntryAbility onDestroy')
    // P3: 停 MCP 网络层（释放端口与连接）
    MCPServer.stop().catch((e: BusinessError) => {
      console.error('EntryAbility MCPServer stop error: ' + e.code + '/' + e.message)
    })
    // P23a: 停定时器
    ScheduleManager.stop()
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    console.info('BrowserOS KaihongOS EntryAbility onWindowStageCreate')
    // P5: 首启动 Onboarding —— 未完成配置则进入引导页
    // p10a: dark dispatch via AppStorage
    // P44-fix: 原来此处在 await configReady 之前读取,load 未完成时把默认 false 写进
    // AppStorage 且之后无人补写 —— 重启后暗色偏好丢失的根因。移到 config 就绪之后。
    // P16a: 下载管理器初始化（建目录 + 扫描恢复已完成列表）
    try {
      DownloadManager.init(this.context)
    } catch (e) {
      console.error('EntryAbility DownloadManager init error: ' + e)
    }
    // P52-2: harness 连接状态 Preferences 注入（ConnectionManager 连接真实化）
    try {
      ConnectionManager.init(this.context)
    } catch (e) {
      console.error('EntryAbility ConnectionManager init error: ' + e)
    }
    // P16b: 标签会话恢复 —— loadContent 前重建持久化标签（dashboard 永远第一个）+ 注入 prefs context
    try {
      TabManager.setContext(this.context)
      // P55: named tab groups persistence context
      TabGroupManager.setContext(this.context)
      const restoredCount = TabManager.restoreTabs()
      console.info('EntryAbility tabs restored: ' + restoredCount)
    } catch (e) {
      console.error('EntryAbility restoreTabs error: ' + e)
    }
    // P36-fix: 等配置就绪再判定入口页（asset 探测异步 IPC 耗时不可忽略）
    await this.configReady
    // P44-fix: darkMode 必须在配置就绪后写入（此处为 AppStorage 首次权威写入点）
    AppStorage.setOrCreate('darkMode', ConfigManager.get().darkMode)
    console.info('EntryAbility darkMode=' + ConfigManager.get().darkMode + ' sensitiveConfirm=' + ConfigManager.isSensitiveConfirm())
    const entryPage = ConfigManager.isOnboardingCompleted() ? 'pages/BrowserShell' : 'pages/OnboardingPage'
    console.info('EntryAbility entry page: ' + entryPage + ' (onboardingCompleted=' + ConfigManager.isOnboardingCompleted() + ')')
    windowStage.loadContent(entryPage, (err: BusinessError) => {
      if (err.code) {
        console.error(`Failed to load UI content: ${err.message}`)
        return
      }
      console.info('UI content loaded successfully')
    })
  }

  onWindowStageDestroy(): void {
    console.info('BrowserOS KaihongOS EntryAbility onWindowStageDestroy')
  }

  onForeground(): void {
    console.info('BrowserOS KaihongOS EntryAbility onForeground')
  }

  onBackground(): void {
    console.info('BrowserOS KaihongOS EntryAbility onBackground')
  }
}
