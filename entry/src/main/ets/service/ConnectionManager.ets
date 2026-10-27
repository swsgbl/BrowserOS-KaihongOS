import { MCPConnection } from '../model/MCPConnection'
import { ConnectionStatus } from '../common/Types'
import { MCPServer } from './MCPServer'
import { McpEndpointConfig } from './McpEndpointConfig'
import { HarnessAdapters } from './HarnessAdapters'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { preferences } from '@kit.ArkData'
import { http } from '@kit.NetworkKit'
import { common } from '@kit.AbilityKit'

/**
 * P52-2: ConnectionManager rewire.
 *  - connect() = generate copy-ready config via HarnessAdapters + persist
 *    config-ready state (NOT fake-connected; harness CLIs live on the PC).
 *  - testConnection() = real JSON-RPC initialize handshake against the
 *    local /mcp endpoint; only a 200 + serverInfo=browseros_mcp marks the
 *    harness connected (Preferences harness_store: harness_connected_<name>).
 *  - all URLs come from McpEndpointConfig (single source of truth, /mcp).
 */

export class HarnessTool {
  name: string = ''
  displayName: string = ''
  description: string = ''
  configFile: string = ''
  detected: boolean = false
  connected: boolean = false
}

export class ConnectTestResult {
  ok: boolean = false
  message: string = ''
  httpCode: number = 0
}

interface HarnessConnEventData {
  status: string
  port: number
  harness: string
}

/** module-level singletons (ArkTS: no static mutable state on classes) */
let harnessPrefs: preferences.Preferences | null = null
const connections: Map<string, MCPConnection> = new Map()

export class ConnectionManager {
  /** P52: EntryAbility 早期调用，注入 Preferences context */
  static init(context: common.UIAbilityContext): void {
    preferences.getPreferences(context, 'harness_store').then((p: preferences.Preferences): void => {
      harnessPrefs = p
      console.info('[P52] harness_store prefs ready')
    }).catch((e: Object): void => {
      console.error('[P52] harness_store prefs init fail: ' + e)
    })
  }

  /**
   * P52: adapter catalog. The CLIs run on the user's PC — on-device detect
   * is always notInstalled; the UI drives a config-ready state machine.
   */
  static detectInstalledTools(): HarnessTool[] {
    const out: HarnessTool[] = []
    for (const a of HarnessAdapters.list()) {
      const t = new HarnessTool()
      t.name = a.name
      t.displayName = a.displayName
      t.description = a.desc
      t.configFile = a.configPath
      t.detected = false
      t.connected = ConnectionManager.isHarnessConnected(a.name)
      out.push(t)
    }
    return out
  }

  static getConnectedTools(): HarnessTool[] {
    return ConnectionManager.detectInstalledTools().filter((t: HarnessTool): boolean => t.connected)
  }

  private static isHarnessConnected(name: string): boolean {
    if (harnessPrefs === null) {
      return false
    }
    const ts = harnessPrefs.getSync('harness_connected_' + name, 0) as number
    return typeof ts === 'number' && ts > 0
  }

  /**
   * P52-2: connect = 生成可复制配置 + 写沙盒存档 + config_ready 状态。
   * 不再直接置 connected —— 真实握手交给 testConnection()。
   */
  static connect(name: string): boolean {
    const info = HarnessAdapters.get(name)
    if (info === null) {
      console.warn('[P52] connect: unknown harness ' + name)
      return false
    }
    const cfg = McpEndpointConfig.fromServer()
    const json = HarnessAdapters.buildConfigJson(name, cfg)
    StorageManager.save(`${name}_mcp.json`, json).then((ok: boolean): void => {
      console.info(`[P52] config saved ${name}_mcp.json ok=${ok}`)
    }).catch((e: Object): void => {
      console.error('[P52] config save fail: ' + e)
    })
    const conn = new MCPConnection(`harness_${name}_${Date.now()}`, cfg.toUrl(), cfg.token)
    conn.status = ConnectionStatus.CONNECTING
    connections.set(name, conn)
    const ev: HarnessConnEventData = { status: 'config_ready', port: cfg.port, harness: name }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, ev)
    console.info(`[P52] config ready: ${name} -> ${info.configPath} endpoint=${cfg.toUrlWithToken()}`)
    return true
  }

  /**
   * P52-2: 真实握手 —— 设备本机 POST initialize 到 127.0.0.1:{port}/mcp?token=
   * 200 + result.serverInfo.name === 'browseros_mcp' 才算 connected。
   */
  static async testConnection(name: string): Promise<ConnectTestResult> {
    const res = new ConnectTestResult()
    if (!MCPServer.isRunning()) {
      res.message = 'MCP server not running'
      console.error('[P52] testConnection ' + name + ': server not running')
      return res
    }
    const cfg = McpEndpointConfig.fromServer()
    if (cfg.token.length === 0) {
      res.message = 'no auth token'
      return res
    }
    const clientInfo: Record<string, Object> = { 'name': 'browseros-connect-test', 'version': '1.0.0' }
    const caps: Record<string, Object> = {}
    const params: Record<string, Object> = {
      'protocolVersion': '2024-11-05',
      'capabilities': caps,
      'clientInfo': clientInfo
    }
    const rpc: Record<string, Object> = { 'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': params }
    const body = JSON.stringify(rpc)
    console.info(`[P52] testConnection ${name} -> POST ${cfg.toUrlWithToken()}`)
    const client = http.createHttp()
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' } as Record<string, string>,
        extraData: body,
        connectTimeout: 5000,
        readTimeout: 8000
      }
      const resp = await client.request(cfg.toUrlWithToken(), opts)
      res.httpCode = resp.responseCode
      if (resp.responseCode !== 200) {
        res.message = 'HTTP ' + resp.responseCode
        console.error(`[P52] testConnection ${name} FAIL: ${res.message}`)
        return res
      }
      const text = typeof resp.result === 'string' ? resp.result as string : JSON.stringify(resp.result)
      const parsed = JSON.parse(text) as Record<string, Object>
      const result = parsed['result'] as Record<string, Object>
      const serverInfo = result !== undefined ? result['serverInfo'] as Record<string, Object> : undefined
      if (serverInfo !== undefined && serverInfo['name'] === 'browseros_mcp') {
        res.ok = true
        res.message = `connected: ${serverInfo['name']} v${serverInfo['version']} (proto ${result !== undefined ? result['protocolVersion'] : '?'})`
        ConnectionManager.markConnected(name, cfg)
      } else {
        res.message = 'unexpected initialize response'
      }
      console.info(`[P52] testConnection ${name} -> ${res.ok ? 'OK' : 'FAIL'}: ${res.message}`)
      return res
    } catch (e) {
      res.message = 'request error: ' + e
      console.error('[P52] testConnection ' + name + ' error: ' + e)
      return res
    } finally {
      client.destroy()
    }
  }

  static markConnected(name: string, cfg: McpEndpointConfig): void {
    const conn = connections.get(name)
    if (conn !== undefined) {
      conn.connect()
    } else {
      const fresh = new MCPConnection(`harness_${name}_${Date.now()}`, cfg.toUrl(), cfg.token)
      connections.set(name, fresh)
    }
    if (harnessPrefs !== null) {
      harnessPrefs.putSync('harness_connected_' + name, Date.now())
      harnessPrefs.flush()
    }
    const ev: HarnessConnEventData = { status: 'connected', port: cfg.port, harness: name }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, ev)
  }

  static disconnect(name: string): void {
    connections.delete(name)
    if (harnessPrefs !== null) {
      harnessPrefs.deleteSync('harness_connected_' + name)
      harnessPrefs.flush()
    }
    console.info('[P52] harness disconnected: ' + name)
  }

  /** compat alias — harness_compat_test.py mirrors this contract */
  static generateMCPConfigJSON(name: string): string {
    return HarnessAdapters.buildConfigJson(name, McpEndpointConfig.fromServer())
  }
}
