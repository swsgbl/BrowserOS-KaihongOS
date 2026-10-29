/**
 * P67: 设备智能体注册表 + 任务收件箱（应用侧零进程依赖的收件箱模式）。
 *
 * 背景：普通应用不能 spawn 子进程（API23 无 child_process 公开 API），
 * Claude Code/Codex/hmharness 装在 VM 上，由 VM 终端常驻 runner
 * （tools/device_agent_runner.js）经 MCP loopback 注册并领取任务。
 *
 * 存储（全部走 StorageManager 沙盒文件，断电恢复天然支持）：
 * - device_agents.json           注册表 { name: {name,kind,registeredAt,lastSeen} }
 * - device_agent_tasks/<id>.json 单任务 {taskId,agent,prompt,context,status,result,...}
 *
 * 在线判定（UI 侧）：lastSeen 距今 < 2min。
 */

import { StorageManager } from '../storage/StorageManager'

export class DeviceAgentEntry {
  name: string = ''
  kind: string = '' // claude-code | codex | hmharness | custom
  registeredAt: number = 0
  lastSeen: number = 0
}

export class DeviceAgentTask {
  taskId: string = ''
  agent: string = ''
  kind: string = '' // '' 常规 prompt 任务 | system_update P69 重启即更
  prompt: string = ''
  contextUrl: string = ''
  contextTitle: string = ''
  contextSelection: string = ''
  status: string = 'pending' // pending | running | completed | failed
  result: string = ''
  createdAt: number = 0
  claimedAt: number = 0
  completedAt: number = 0
}

const REGISTRY_PATH = 'device_agents.json'
const TASKS_DIR = 'device_agent_tasks'
const ONLINE_WINDOW_MS = 2 * 60 * 1000

function now(): number {
  return new Date().getTime()
}

class DeviceAgentStoreImpl {
  private cache: Record<string, Object> | null = null

  /** 注册（新 agent 或心跳重注册）：lastSeen 刷新 */
  async register(name: string, kind: string): Promise<DeviceAgentEntry> {
    const reg = await this.loadRegistry()
    let entry = reg[name] as Record<string, Object> | undefined
    const e: Record<string, Object> = entry !== undefined ? entry : {}
    e['name'] = name
    e['kind'] = kind
    e['lastSeen'] = now()
    if (entry === undefined) {
      e['registeredAt'] = now()
    }
    reg[name] = e
    this.cache = reg
    await StorageManager.saveJSON(REGISTRY_PATH, reg)
    return this.toEntry(e)
  }

  /** 全量列表（内存缓存 + 文件真值；UI 1s 轮询走此口） */
  async listAgents(): Promise<DeviceAgentEntry[]> {
    const reg = await this.loadRegistry()
    const out: DeviceAgentEntry[] = []
    for (const key of Object.keys(reg)) {
      out.push(this.toEntry(reg[key] as Record<string, Object>))
    }
    // 最近注册在前
    out.sort((a, b) => b.registeredAt - a.registeredAt)
    return out
  }

  isOnline(e: DeviceAgentEntry): boolean {
    return now() - e.lastSeen < ONLINE_WINDOW_MS
  }

  /** UI 提交任务：写 pending 任务文件，等 runner 领取（kind: '' 常规 | system_update P69） */
  async createTask(agentName: string, prompt: string, ctxUrl: string, ctxTitle: string, ctxSel: string,
    kind: string = ''): Promise<DeviceAgentTask> {
    const t = new DeviceAgentTask()
    t.taskId = 'dat_' + now() + '_' + Math.floor(Math.random() * 100000)
    t.agent = agentName
    t.kind = kind
    t.prompt = prompt
    t.contextUrl = ctxUrl
    t.contextTitle = ctxTitle
    t.contextSelection = ctxSel
    t.status = 'pending'
    t.createdAt = now()
    await StorageManager.saveJSON(`${TASKS_DIR}/${t.taskId}.json`, this.taskToRecord(t))
    return t
  }

  /** runner 领取：最早创建的 pending → running */
  async claimNext(agentName: string): Promise<DeviceAgentTask | null> {
    const ids = await StorageManager.listDir(TASKS_DIR)
    let best: DeviceAgentTask | null = null
    for (const f of ids) {
      if (!f.endsWith('.json')) {
        continue
      }
      const rec = await StorageManager.loadJSON(`${TASKS_DIR}/${f}`)
      if (rec === null) {
        continue
      }
      const t = this.toTask(rec)
      if (t.agent !== agentName || t.status !== 'pending') {
        continue
      }
      if (best === null || t.createdAt < best.createdAt) {
        best = t
      }
    }
    if (best !== null) {
      best.status = 'running'
      best.claimedAt = now()
      await StorageManager.saveJSON(`${TASKS_DIR}/${best.taskId}.json`, this.taskToRecord(best))
    }
    return best
  }

  /** runner 回写结果 */
  async completeTask(taskId: string, ok: boolean, result: string): Promise<DeviceAgentTask | null> {
    const rec = await StorageManager.loadJSON(`${TASKS_DIR}/${taskId}.json`)
    if (rec === null) {
      return null
    }
    const t = this.toTask(rec)
    t.status = ok ? 'completed' : 'failed'
    // 32KB 截断（与 MCP 消息上限同量级）
    t.result = result.length > 32768 ? result.substring(0, 32768) + '…' : result
    t.completedAt = now()
    await StorageManager.saveJSON(`${TASKS_DIR}/${t.taskId}.json`, this.taskToRecord(t))
    return t
  }

  /** UI 轮询指定任务 */
  async getTask(taskId: string): Promise<DeviceAgentTask | null> {
    const rec = await StorageManager.loadJSON(`${TASKS_DIR}/${taskId}.json`)
    return rec === null ? null : this.toTask(rec)
  }

  private async loadRegistry(): Promise<Record<string, Object>> {
    if (this.cache !== null) {
      return this.cache
    }
    const rec = await StorageManager.loadJSON(REGISTRY_PATH)
    this.cache = rec !== null ? rec : {}
    return this.cache
  }

  /** 强制重载（注册表被外部 MCP 写过之后 UI 需要最新值时用） */
  async reload(): Promise<void> {
    this.cache = null
    await this.loadRegistry()
  }

  private toEntry(e: Record<string, Object>): DeviceAgentEntry {
    const out = new DeviceAgentEntry()
    out.name = `${e['name'] ?? ''}`
    out.kind = `${e['kind'] ?? 'custom'}`
    out.registeredAt = e['registeredAt'] as number
    out.lastSeen = e['lastSeen'] as number
    return out
  }

  private toTask(r: Record<string, Object>): DeviceAgentTask {
    const t = new DeviceAgentTask()
    t.taskId = `${r['taskId'] ?? ''}`
    t.agent = `${r['agent'] ?? ''}`
    t.kind = `${r['kind'] ?? ''}`
    t.prompt = `${r['prompt'] ?? ''}`
    t.contextUrl = `${r['contextUrl'] ?? ''}`
    t.contextTitle = `${r['contextTitle'] ?? ''}`
    t.contextSelection = `${r['contextSelection'] ?? ''}`
    t.status = `${r['status'] ?? 'pending'}`
    t.result = `${r['result'] ?? ''}`
    t.createdAt = r['createdAt'] as number
    t.claimedAt = r['claimedAt'] as number
    t.completedAt = r['completedAt'] as number
    return t
  }

  private taskToRecord(t: DeviceAgentTask): Record<string, Object> {
    const r: Record<string, Object> = {}
    r['taskId'] = t.taskId
    r['agent'] = t.agent
    r['kind'] = t.kind
    r['prompt'] = t.prompt
    r['contextUrl'] = t.contextUrl
    r['contextTitle'] = t.contextTitle
    r['contextSelection'] = t.contextSelection
    r['status'] = t.status
    r['result'] = t.result
    r['createdAt'] = t.createdAt
    r['claimedAt'] = t.claimedAt
    r['completedAt'] = t.completedAt
    return r
  }
}

export const DeviceAgentStore = new DeviceAgentStoreImpl()
