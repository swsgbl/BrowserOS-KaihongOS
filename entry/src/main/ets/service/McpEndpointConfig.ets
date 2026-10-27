import { MCPServer } from './MCPServer'
import { ConfigManager } from '../storage/ConfigManager'

/**
 * P52: single source of truth for the MCP endpoint exposed to harnesses.
 * All config generators (ConnectionManager / HarnessAdapters / UI display)
 * must build URLs from this class — no more /sse vs /mcp drift.
 *
 * Reality: HttpMcpTransport listens on device loopback 127.0.0.1:{port}
 * (P42 hardening), so harness CLIs on the user's PC reach it through an
 * hdc fport tunnel:  hdc fport tcp:{port} tcp:{port}  → 127.0.0.1:{port}.
 */
export class McpEndpointConfig {
  protocol: string = 'http'
  host: string = '127.0.0.1'
  port: number = 9222
  path: string = '/mcp'        // P52: unified streamable-HTTP endpoint (was /sse drift)
  token: string = ''
  transport: string = 'streamable-http'

  /** effective port: live server port, else configured port */
  static currentPort(): number {
    return MCPServer.isRunning() ? MCPServer.getPort() : ConfigManager.getMcpPort()
  }

  /** snapshot of the running (or configured) server endpoint */
  static fromServer(): McpEndpointConfig {
    const cfg = new McpEndpointConfig()
    cfg.port = McpEndpointConfig.currentPort()
    cfg.token = MCPServer.getAuthToken()
    return cfg
  }

  /** base URL without credentials */
  toUrl(): string {
    return `${this.protocol}://${this.host}:${this.port}${this.path}`
  }

  /** URL with inline token (what harness configs embed) */
  toUrlWithToken(): string {
    const t = this.token.length > 0 ? this.token : '<token>'
    return `${this.toUrl()}?token=${t}`
  }

  /** P52: canonical endpoint string for UI display */
  getEndpoint(): string {
    return this.toUrlWithToken()
  }

  /** LAN placeholder form (shown in hero card; device IP is host-dependent) */
  lanUrlWithToken(): string {
    const t = this.token.length > 0 ? this.token : '<token>'
    return `${this.protocol}://<本机IP>:${this.port}${this.path}?token=${t}`
  }

  /**
   * P52: host-side port-forward command. Run on the PC where harness CLIs
   * live; maps host 127.0.0.1:{port} → device loopback {port}.
   * target: optional hdc target id (e.g. 192.168.161.137:10178)
   */
  fportCommand(target: string): string {
    const base = `hdc fport tcp:${this.port} tcp:${this.port}`
    return target.length > 0 ? `${base} -t ${target}` : base
  }
}
