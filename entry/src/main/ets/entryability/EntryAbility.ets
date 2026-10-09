import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { StorageManager } from '../storage/StorageManager'
import { ConfigManager } from '../storage/ConfigManager'
import { MCPServer } from '../service/MCPServer'
import { HistoryManager } from '../service/HistoryManager'
import { LoginStateManager } from '../service/LoginStateManager'
import { SessionManager } from '../service/SessionManager'
import { DownloadManager } from '../service/DownloadManager'
import { TabManager } from '../service/TabManager'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('BrowserOS KaihongOS EntryAbility onCreate')
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
    ConfigManager.load().then((config) => {
      console.info('EntryAbility ConfigManager loaded, mcpPort=' + config.mcpPort)
      // P3: 启动 MCP 网络层（HTTP transport 监听 0.0.0.0:{mcpPort}，token 每次启动新生成）
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
    }).catch((e: BusinessError) => {
      console.error('EntryAbility ConfigManager load error: ' + e.message)
    })
  }

  onDestroy(): void {
    console.info('BrowserOS KaihongOS EntryAbility onDestroy')
    // P3: 停 MCP 网络层（释放端口与连接）
    MCPServer.stop().catch((e: BusinessError) => {
      console.error('EntryAbility MCPServer stop error: ' + e.code + '/' + e.message)
    })
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('BrowserOS KaihongOS EntryAbility onWindowStageCreate')
    // P5: 首启动 Onboarding —— 未完成配置则进入引导页
    // p10a: dark dispatch via AppStorage
    AppStorage.setOrCreate('darkMode', ConfigManager.get().darkMode)
    console.info('EntryAbility darkMode=' + ConfigManager.get().darkMode + ' sensitiveConfirm=' + ConfigManager.isSensitiveConfirm())
    // P16a: 下载管理器初始化（建目录 + 扫描恢复已完成列表）
    try {
      DownloadManager.init(this.context)
    } catch (e) {
      console.error('EntryAbility DownloadManager init error: ' + e)
    }
    // P16b: 标签会话恢复 —— loadContent 前重建持久化标签（dashboard 永远第一个）+ 注入 prefs context
    try {
      TabManager.setContext(this.context)
      const restoredCount = TabManager.restoreTabs()
      console.info('EntryAbility tabs restored: ' + restoredCount)
    } catch (e) {
      console.error('EntryAbility restoreTabs error: ' + e)
    }
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
