/**
 * P23a: 定时任务管理器 —— cron 式代理任务调度
 * - 数据模型 ScheduleTask（hourly/daily/weekly + timeOfDay 简化 cron）
 * - StorageManager.saveJSON/loadJSON 持久化 schedules.json（{"tasks":[...]}）
 * - 1 分钟 tick：到点 → AgentEngine.createAgent(ONCE) → 终态轮询 → lastResult(200字)+lastRunAt
 * - EventBus SCHEDULES_CHANGED 通知页面刷新
 */
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { AgentEngine } from './AgentEngine'
import { AgentStatus } from '../common/Types'

export class ScheduleTask {
  id: string = ''
  name: string = ''
  prompt: string = ''
  targetUrl: string = ''
  interval: string = 'daily' // 'hourly' | 'daily' | 'weekly'
  timeOfDay: string = '09:00' // daily/weekly 用 'HH:mm'
  enabled: boolean = true
  lastRunAt: number = 0
  lastResult: string = ''
  createdAt: number = 0

  constructor(id: string, name: string, prompt: string, targetUrl: string,
    interval: string, timeOfDay: string, enabled: boolean, createdAt: number) {
    this.id = id
    this.name = name
    this.prompt = prompt
    this.targetUrl = targetUrl
    this.interval = interval
    this.timeOfDay = timeOfDay
    this.enabled = enabled
    this.createdAt = createdAt
  }
}

interface ScheduleTasksJSON {
  tasks: ScheduleTask[]
}

/** 判定所需时刻上下文（便于复现测试） */
interface TickContext {
  now: number
  hour: number
  minute: number
  dayOfWeek: number // 0=Sun .. 1=Mon .. 6=Sat
}

class ScheduleManagerImpl {
  private tasks: ScheduleTask[] = []
  private loaded: boolean = false
  private timerId: number = -1
  /** 防重入：正在执行轮次的任务 id */
  private runningRounds: Set<string> = new Set()

  /** 应用启动时初始化（EntryAbility onCreate，ConfigManager.load 后调用） */
  async init(): Promise<void> {
    if (this.loaded) {
      return
    }
    await this.load()
    this.loaded = true
    if (this.timerId < 0) {
      this.timerId = setInterval(() => {
        this.tick()
      }, 60000)
    }
    console.info('[ScheduleManager] init done, tasks=' + this.tasks.length)
  }

  /** 停止定时器（EntryAbility onDestroy） */
  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  async load(): Promise<void> {
    const obj = await StorageManager.loadJSON('schedules.json')
    this.tasks = []
    if (obj !== null) {
      const raw = obj['tasks'] as ScheduleTask[]
      if (raw !== null && raw !== undefined) {
        this.tasks = raw
      }
    }
  }

  private async persist(): Promise<void> {
    const payload: ScheduleTasksJSON = { tasks: this.tasks }
    await StorageManager.saveJSON('schedules.json', payload)
  }

  getTasks(): ScheduleTask[] {
    return this.tasks
  }

  getTask(id: string): ScheduleTask | null {
    for (const t of this.tasks) {
      if (t.id === id) {
        return t
      }
    }
    return null
  }

  addTask(name: string, prompt: string, targetUrl: string, interval: string, timeOfDay: string): ScheduleTask {
    const task = new ScheduleTask(
      'sch_' + Date.now() + '_' + Math.random().toString(36).substring(2, 8),
      name, prompt, targetUrl, interval, timeOfDay, true, Date.now())
    this.tasks.push(task)
    this.persist().then(() => {
      EventBus.emit(EventBusEvents.SCHEDULES_CHANGED)
    })
    console.info('[ScheduleManager] task added: ' + task.id + ' name=' + name + ' interval=' + interval)
    return task
  }

  removeTask(id: string): void {
    this.tasks = this.tasks.filter((t: ScheduleTask) => t.id !== id)
    this.persist().then(() => {
      EventBus.emit(EventBusEvents.SCHEDULES_CHANGED)
    })
    console.info('[ScheduleManager] task removed: ' + id)
  }

  setEnabled(id: string, enabled: boolean): void {
    const t = this.getTask(id)
    if (t !== null) {
      t.enabled = enabled
      this.persist().then(() => {
        EventBus.emit(EventBusEvents.SCHEDULES_CHANGED)
      })
    }
  }

  /** 页面「立即运行」与定时到点共用入口 */
  runNow(id: string): boolean {
    const task = this.getTask(id)
    if (task === null) {
      return false
    }
    if (this.runningRounds.has(id)) {
      console.warn('[ScheduleManager] round already running: ' + id)
      return false
    }
    this.runningRounds.add(id)
    const agent = AgentEngine.createAgent(task.name, task.targetUrl, task.prompt)
    if (agent === null) {
      this.runningRounds.delete(id)
      task.lastRunAt = Date.now()
      task.lastResult = '失败：代理数已达上限，稍后自动重试'
      this.persist().then(() => {
        EventBus.emit(EventBusEvents.SCHEDULES_CHANGED)
      })
      console.warn('[ScheduleManager] createAgent rejected (max agents): ' + task.name)
      return false
    }
    this.watchRound(id, agent.agentId)
    return true
  }

  /** 终态轮询：agent 到 COMPLETED/ERROR/STOPPED 后写结果 */
  private watchRound(taskId: string, agentId: string): void {
    let polls = 0
    const maxPolls = 120 // 120 * 5s = 10 分钟上限
    const timer = setInterval(() => {
      polls++
      const task = this.getTask(taskId)
      if (task === null) {
        clearInterval(timer)
        this.runningRounds.delete(taskId)
        return
      }
      const st = AgentEngine.getAgentStatus(agentId)
      if (st === null) {
        // agent 已被清理，读终态答案库兜底
        this.finishRound(task, agentId, timer)
        return
      }
      if (st.status === AgentStatus.COMPLETED || st.status === AgentStatus.ERROR || st.status === AgentStatus.STOPPED) {
        this.finishRound(task, agentId, timer)
        return
      }
      if (polls >= maxPolls) {
        task.lastRunAt = Date.now()
        task.lastResult = '超时：本轮未在 10 分钟内完成'
        clearInterval(timer)
        this.runningRounds.delete(taskId)
        this.persist().then(() => {
          EventBus.emit(EventBusEvents.SCHEDULES_CHANGED)
        })
      }
    }, 5000)
  }

  private finishRound(task: ScheduleTask, agentId: string, timer: number): void {
    clearInterval(timer)
    this.runningRounds.delete(task.id)
    const answer = AgentEngine.getFinalAnswer(agentId)
    task.lastRunAt = Date.now()
    task.lastResult = answer !== null
      ? (answer.length > 200 ? answer.substring(0, 200) + '…' : answer)
      : '(无终态结果)'
    this.persist().then(() => {
      EventBus.emit(EventBusEvents.SCHEDULES_CHANGED)
    })
    console.info('[ScheduleManager] round finished: ' + task.name + ' result=' + task.lastResult.substring(0, 80))
  }

  /** 1 分钟 tick：规则匹配则触发 runNow */
  tick(): void {
    if (this.tasks.length === 0) {
      return
    }
    const d = new Date()
    const ctx: TickContext = {
      now: d.getTime(),
      hour: d.getHours(),
      minute: d.getMinutes(),
      dayOfWeek: d.getDay()
    }
    for (const task of this.tasks) {
      if (!task.enabled) {
        continue
      }
      if (this.runningRounds.has(task.id)) {
        continue
      }
      if (this.isDue(task, ctx)) {
        console.info('[ScheduleManager] due task firing: ' + task.name + ' (' + task.interval + ')')
        this.runNow(task.id)
      }
    }
  }

  /** 调度规则判定（纯函数，便于测试） */
  isDue(task: ScheduleTask, ctx: TickContext): boolean {
    const HOUR_MS = 3600000
    if (task.interval === 'hourly') {
      return ctx.now - task.lastRunAt >= HOUR_MS
    }
    if (task.interval === 'daily') {
      return this.matchedTodayButNotYetRun(task, ctx)
    }
    if (task.interval === 'weekly') {
      if (ctx.dayOfWeek !== 1) {
        return false
      }
      return this.matchedTodayButNotYetRun(task, ctx)
    }
    return false
  }

  /** daily/weekly 共用：今天 timeOfDay 已到点且本轮未跑 */
  private matchedTodayButNotYetRun(task: ScheduleTask, ctx: TickContext): boolean {
    const scheduled = this.parseTimeOfDay(task.timeOfDay)
    if (scheduled < 0) {
      return false
    }
    const nowMin = ctx.hour * 60 + ctx.minute
    if (nowMin < scheduled) {
      return false
    }
    // lastRunAt 是否在今天 scheduled 之前（含 1 分钟容差）？
    const d = new Date(ctx.now)
    const schedTs = new Date(d.getFullYear(), d.getMonth(), d.getDate(),
      Math.floor(scheduled / 60), scheduled % 60, 0, 0).getTime()
    return task.lastRunAt < schedTs - 60000
  }

  /** 'HH:mm' → 当日分钟数；非法返回 -1 */
  private parseTimeOfDay(s: string): number {
    if (s === null || s === undefined || s.length === 0) {
      return -1
    }
    const m = s.trim().match(/^(\d{1,2}):(\d{2})$/)
    if (m === null) {
      return -1
    }
    const h = parseInt(m[1], 10)
    const mi = parseInt(m[2], 10)
    if (Number.isNaN(h) || Number.isNaN(mi) || h < 0 || h > 23 || mi < 0 || mi > 59) {
      return -1
    }
    return h * 60 + mi
  }
}

export const ScheduleManager = new ScheduleManagerImpl()
