import { McpEndpointConfig } from './McpEndpointConfig'

/**
 * P52: harness adapters — generate copy-ready MCP config JSON for the
 * mainstream coding CLIs. The CLIs run on the user's PC (not on the
 * device), so "detect" on-device is meaningless: the UX is a config-ready
 * state machine (Connect → copy config → copy fport cmd → Test → Connected).
 *
 * Shapes (top-level key + entry fields per CLI family):
 *  - claude-code  ~/.claude.json        mcpServers.{name}.{type:'http', url}
 *  - codex        ~/.codex/config.json  mcpServers.{name}.{transport:'http', url}
 *  - cursor       ~/.cursor/mcp.json    mcpServers.{name}.{url}
 *  - generic      any MCP client        mcpServers.{name}.{type:'http', url}
 */
export class HarnessAdapterInfo {
  name: string = ''
  displayName: string = ''
  configPath: string = ''
  desc: string = ''
}

export class HarnessAdapters {
  static list(): HarnessAdapterInfo[] {
    const a = new HarnessAdapterInfo()
    a.name = 'claude-code'
    a.displayName = 'Claude Code'
    a.configPath = '~/.claude.json'
    a.desc = 'Anthropic Claude Code CLI'

    const b = new HarnessAdapterInfo()
    b.name = 'codex'
    b.displayName = 'Codex'
    b.configPath = '~/.codex/config.json'
    b.desc = 'OpenAI Codex CLI'

    const c = new HarnessAdapterInfo()
    c.name = 'cursor'
    c.displayName = 'Cursor'
    c.configPath = '~/.cursor/mcp.json'
    c.desc = 'Cursor IDE'

    const d = new HarnessAdapterInfo()
    d.name = 'generic'
    d.displayName = 'Generic MCP'
    d.configPath = 'any MCP client config'
    d.desc = 'Standard mcpServers JSON'

    return [a, b, c, d]
  }

  static get(name: string): HarnessAdapterInfo | null {
    for (const h of HarnessAdapters.list()) {
      if (h.name === name) {
        return h
      }
    }
    return null
  }

  /** copy-ready config JSON for one harness (url + inline token) */
  static buildConfigJson(name: string, cfg: McpEndpointConfig): string {
    const url = cfg.toUrlWithToken()
    let inner: string
    if (name === 'codex') {
      inner = `{"transport":"http","url":"${url}"}`
    } else if (name === 'cursor') {
      inner = `{"url":"${url}"}`
    } else {
      // claude-code + generic
      inner = `{"type":"http","url":"${url}"}`
    }
    return `{\n  "mcpServers": {\n    "browseros-kaihongos": ${inner}\n  }\n}`
  }

  static getFportCommand(cfg: McpEndpointConfig, target: string): string {
    return cfg.fportCommand(target)
  }

  /** full clipboard payload: fport command + config JSON + target file hint */
  static getClipboardText(name: string, cfg: McpEndpointConfig, target: string): string {
    const info = HarnessAdapters.get(name)
    const path = info !== null ? info.configPath : 'mcp config'
    return `# 1) port-forward (run on PC):\n${cfg.fportCommand(target)}\n# 2) merge into ${path}:\n${HarnessAdapters.buildConfigJson(name, cfg)}`
  }
}
