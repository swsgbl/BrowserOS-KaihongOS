type EventHandler = (data: Object) => void

class EventBusImpl {
  private handlers: Map<string, EventHandler[]> = new Map()

  on(event: string, handler: EventHandler): void {
    if (!this.handlers.has(event)) {
      this.handlers.set(event, [])
    }
    this.handlers.get(event)!.push(handler)
  }

  off(event: string, handler: EventHandler): void {
    const list = this.handlers.get(event)
    if (list) {
      const idx = list.indexOf(handler)
      if (idx >= 0) {
        list.splice(idx, 1)
      }
      if (list.length === 0) {
        this.handlers.delete(event)
      }
    }
  }

  emit(event: string, data?: Object): void {
    const list = this.handlers.get(event)
    if (list) {
      const eventData: Object = data !== undefined ? data : ''
      for (const handler of list) {
        try {
          handler(eventData)
        } catch (e) {
          console.error(`EventBus handler error for ${event}: ${e}`)
        }
      }
    }
  }

  clear(event?: string): void {
    if (event) {
      this.handlers.delete(event)
    } else {
      this.handlers.clear()
    }
  }
}

export const EventBus = new EventBusImpl()

export class EventBusEvents {
  static readonly AGENT_STATUS_CHANGE: string = 'agent_status_change'
  static readonly AGENT_HEARTBEAT: string = 'agent_heartbeat'
  static readonly TAB_STATUS_CHANGE: string = 'tab_status_change'
  static readonly MCP_CONNECTION_CHANGE: string = 'mcp_connection_change'
  static readonly MCP_TOOL_CALL: string = 'mcp_tool_call'
  static readonly MCP_TOOL_RESPONSE: string = 'mcp_tool_response'
  static readonly SESSION_RECORDING_START: string = 'session_recording_start'
  static readonly SESSION_RECORDING_STOP: string = 'session_recording_stop'
  static readonly SENSITIVE_OPERATION_DETECTED: string = 'sensitive_operation_detected'
  static readonly SENSITIVE_OPERATION_CONFIRMED: string = 'sensitive_operation_confirmed'
  static readonly SENSITIVE_OPERATION_REJECTED: string = 'sensitive_operation_rejected'
  static readonly CONFIG_CHANGE: string = 'config_change'
  static readonly ERROR_OCCURRED: string = 'error_occurred'
  static readonly DASHBOARD_UPDATE: string = 'dashboard_update'
  static readonly LOGIN_STATE_IMPORTED: string = 'login_state_imported'
  static readonly BOOKMARKS_CHANGED: string = 'bookmarks_changed'
  static readonly HISTORY_CHANGED: string = 'history_changed'
  static readonly ONBOARDING_STEP_CHANGE: string = 'onboarding_step_change'
  static readonly PAGE_LOAD_COMPLETE: string = 'page_load_complete'
  static readonly PAGE_LOAD_ERROR: string = 'page_load_error'
  static readonly DOC_MILESTONE_STATUS_CHANGE: string = 'doc-milestone-status-changed'
  static readonly DOC_PROBLEM_ESCALATED: string = 'doc-problem-escalated'
  static readonly DOC_VERSION_RELEASED: string = 'doc-version-released'
  static readonly DOC_CONFIG_CHANGE: string = 'doc-config-changed'
}