export class Constants {
  static readonly DEFAULT_MCP_PORT: number = 9222
  static readonly MAX_AGENTS: number = 5
  static readonly DEFAULT_RECORDING_QUALITY: string = 'medium'
  static readonly SNAPSHOT_COMPRESSION_RATIO: number = 0.3
  static readonly MCP_CALL_TIMEOUT_MS: number = 10000
  static readonly PAGE_LOAD_TIMEOUT_MS: number = 15000
  static readonly AGENT_TIMEOUT_MINUTES: number = 5
  static readonly HEARTBEAT_INTERVAL_MS: number = 1000
  static readonly MCP_RECONNECT_INTERVAL_MS: number = 3000
  static readonly MCP_RECONNECT_MAX_ATTEMPTS: number = 3
  static readonly RECORDING_MAX_SPACE_MB: number = 500
  static readonly DASHBOARD_REFRESH_INTERVAL_MS: number = 1000
  static readonly DASHBOARD_PULL_INTERVAL_MS: number = 5000
  static readonly VIRTUAL_LIST_THRESHOLD: number = 20
  static readonly DEFAULT_SEARCH_ENGINE: string = 'https://www.google.com/search?q='
  static readonly BCP_SCRIPT_INJECT_TIMEOUT_MS: number = 5000
  static readonly SCREENSHOT_QUALITY_MAP: Record<string, number> = {
    'low': 0.3,
    'medium': 0.6,
    'high': 1.0
  }
  static readonly RECORDING_INTERVAL_MAP: Record<string, number> = {
    'low': 5000,
    'medium': 2000,
    'high': 1000
  }
  static readonly STORAGE_BASE_PATH: string = '/data/storage'
  static readonly AGENTS_PATH: string = '/data/storage/agents/'
  static readonly TABS_PATH: string = '/data/storage/tabs/'
  static readonly SESSIONS_PATH: string = '/data/storage/sessions/'
  static readonly CONNECTIONS_FILE: string = '/data/storage/connections.json'
  static readonly LOGIN_STATE_PATH: string = '/data/storage/login_state/'
  static readonly AUDIT_PATH: string = '/data/storage/audit/'
  static readonly CONFIG_FILE: string = '/data/storage/config.json'
  static readonly AUTH_TOKEN_LENGTH: number = 32
  static readonly REPLAY_SPEEDS: number[] = [0.5, 1, 2, 4]
  static readonly MAX_PARALLEL_AGENTS: number = 5
  static readonly MEMORY_LIMIT_MB: number = 512
  static readonly STABILITY_TEST_HOURS: number = 24
  static readonly CRASH_RECOVERY_MS: number = 5000
}