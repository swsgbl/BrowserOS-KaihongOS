import { DocManagementInitializer } from './DocManagementInitializer'
import { DevPlanManager } from './business/DevPlanManager'
import { DevLogManager } from './business/DevLogManager'
import { ChangelogManager } from './business/ChangelogManager'
import { StatusReportGenerator } from './business/StatusReportGenerator'
import { MeetingMinutesManager } from './business/MeetingMinutesManager'
import { ADRManager } from './business/ADRManager'
import { DocConfigManager } from './storage/DocConfigManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'

class DocManagementFacadeImpl {
  private initialized: boolean = false

  async initialize(): Promise<boolean> {
    if (this.initialized) {
      return true
    }
    const initResult = await DocManagementInitializer.initialize()
    if (!initResult.allDirsCreated) {
      return false
    }
    await DocConfigManager.loadConfig()
    await DevPlanManager.loadDataSnapshot()
    await DevLogManager.loadDataSnapshot()
    await ADRManager.loadDataSnapshot()
    await ChangelogManager.loadDataSnapshot()
    await MeetingMinutesManager.loadDataSnapshot()
    this.setupEventWiring()
    this.initialized = true
    return true
  }

  private setupEventWiring(): void {
    EventBus.on(EventBusEvents.DOC_MILESTONE_STATUS_CHANGE, (data: Object) => {
      console.info(`[DocMgmt] milestone status changed: ${JSON.stringify(data)}`)
    })
    EventBus.on(EventBusEvents.DOC_PROBLEM_ESCALATED, (data: Object) => {
      console.info(`[DocMgmt] problem escalated to risk: ${JSON.stringify(data)}`)
    })
    EventBus.on(EventBusEvents.DOC_VERSION_RELEASED, (data: Object) => {
      console.info(`[DocMgmt] version released: ${JSON.stringify(data)}`)
    })
  }

  getDevPlanManager(): typeof DevPlanManager {
    return DevPlanManager
  }

  getDevLogManager(): typeof DevLogManager {
    return DevLogManager
  }

  getChangelogManager(): typeof ChangelogManager {
    return ChangelogManager
  }

  getStatusReportGenerator(): typeof StatusReportGenerator {
    return StatusReportGenerator
  }

  getMeetingMinutesManager(): typeof MeetingMinutesManager {
    return MeetingMinutesManager
  }

  getADRManager(): typeof ADRManager {
    return ADRManager
  }

  isInitialized(): boolean {
    return this.initialized
  }
}

export const DocManagementFacade = new DocManagementFacadeImpl()