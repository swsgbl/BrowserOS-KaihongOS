export enum RunStrategy {
  ONCE = 'once',
  LOOP = 'loop',
  SCHEDULED = 'scheduled'
}

export enum AgentStatus {
  IDLE = 'idle',
  RUNNING = 'running',
  COMPLETED = 'completed',
  ERROR = 'error',
  STOPPED = 'stopped',
  PAUSED = 'paused'
}

export enum TabStatus {
  LOADING = 'loading',
  IDLE = 'idle',
  INTERACTING = 'interacting',
  ERROR = 'error'
}

export enum ToolType {
  NAVIGATE = 'navigate',
  CLICK = 'click',
  TYPE = 'type',
  SCREENSHOT = 'screenshot',
  SNAPSHOT = 'snapshot',
  SCROLL = 'scroll',
  GET_TEXT = 'getText',
  WAIT = 'wait',
  BACK = 'back',
  FORWARD = 'forward'
}

export enum ConnectionStatus {
  CONNECTED = 'connected',
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting'
}

export enum RecordingQuality {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high'
}

export enum OperationResult {
  SUCCESS = 'success',
  FAILED = 'failed',
  PENDING = 'pending',
  REJECTED = 'rejected'
}

export enum SensitiveOperationType {
  FORM_SUBMIT = 'form_submit',
  PAYMENT = 'payment',
  DELETE = 'delete',
  SETTINGS_CHANGE = 'settings_change',
  UNSPECIFIED_NAVIGATION = 'unspecified_navigation'
}

export interface BCPResult {
  success: boolean
  data: string | null
  error: string | null
}

export interface MCPToolResponse {
  status: string
  data: Object | null
  error: string | null
  requestId: string
}