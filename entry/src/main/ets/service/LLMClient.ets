import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'

/** OpenAI 协议嵌套对象的显式类（ArkTS 严格模式：禁止无类型对象字面量） */
class LLMFunctionJSON {
  name: string = ''
  arguments: string = '{}'
}

class LLMToolCallJSON {
  id: string = ''
  type: string = 'function'
  function: LLMFunctionJSON = new LLMFunctionJSON()
}

class LLMMessageJSON {
  role: string = ''
  content: string = ''
  tool_calls: LLMToolCallJSON[] | null = null
  tool_call_id: string = ''
}

class LLMToolFunctionJSON {
  name: string = ''
  description: string = ''
  parameters: LLMParamsJSON = new LLMParamsJSON()
}

class LLMToolJSON {
  type: string = 'function'
  function: LLMToolFunctionJSON = new LLMToolFunctionJSON()
}

class LLMRequestBody {
  model: string = ''
  messages: LLMMessageJSON[] = []
  tool_choice: string = 'auto'
  stream: boolean = false
  tools: Record<string, Object>[] | null = null
}

/** JSON Schema 参数描述（工具表用） */
export class LLMParamProp {
  type: string = 'string'
  description: string = ''

  constructor(type: string, description: string) {
    this.type = type
    this.description = description
  }
}

/** schema 的 key->prop 序对（避免 Record 字面量） */
export class LLMParamEntry {
  key: string = ''
  prop: LLMParamProp = new LLMParamProp('string', '')

  constructor(key: string, prop: LLMParamProp) {
    this.key = key
    this.prop = prop
  }
}

class LLMParamsJSON {
  type: string = 'object'
  properties: Record<string, LLMParamProp> = {}
  required: string[] = []
}

export class LLMParamsSchema {
  type: string = 'object'
  entries: LLMParamEntry[] = []
  required: string[] = []

  toJSON(): LLMParamsJSON {
    const json = new LLMParamsJSON()
    json.type = this.type
    const props: Record<string, LLMParamProp> = {}
    for (const entry of this.entries) {
      props[entry.key] = entry.prop
    }
    json.properties = props
    json.required = this.required
    return json
  }
}

export interface LLMToolSpec {
  name: string
  description: string
  parameters: LLMParamsSchema
}

/**
 * OpenAI 兼容 ChatMessage（/v1/chat/completions 协议子集）
 * role: system / user / assistant / tool
 */
export class LLMChatMessage {
  role: string = 'user'
  content: string | null = null
  tool_calls: LLMToolCall[] | null = null
  tool_call_id: string = ''

  static system(text: string): LLMChatMessage {
    const m = new LLMChatMessage()
    m.role = 'system'
    m.content = text
    return m
  }

  static user(text: string): LLMChatMessage {
    const m = new LLMChatMessage()
    m.role = 'user'
    m.content = text
    return m
  }

  static assistant(content: string | null, toolCalls: LLMToolCall[] | null): LLMChatMessage {
    const m = new LLMChatMessage()
    m.role = 'assistant'
    m.content = content
    m.tool_calls = toolCalls
    return m
  }

  static toolResult(toolCallId: string, text: string): LLMChatMessage {
    const m = new LLMChatMessage()
    m.role = 'tool'
    m.tool_call_id = toolCallId
    m.content = text
    return m
  }

  toJSON(): LLMMessageJSON {
    const obj = new LLMMessageJSON()
    obj.role = this.role
    obj.content = this.content === null ? '' : this.content
    if (this.role === 'assistant' && this.tool_calls && this.tool_calls.length > 0) {
      obj.tool_calls = this.tool_calls.map(c => c.toJSON())
    }
    if (this.role === 'tool') {
      obj.tool_call_id = this.tool_call_id
    }
    return obj
  }
}

/** LLM 返回的一次工具调用请求 */
export class LLMToolCall {
  id: string = ''
  type: string = 'function'
  function_name: string = ''
  function_args: string = '{}'

  constructor(id: string, name: string, args: string) {
    this.id = id
    this.function_name = name
    this.function_args = args
  }

  toJSON(): LLMToolCallJSON {
    const obj = new LLMToolCallJSON()
    obj.id = this.id
    obj.type = this.type
    obj.function = new LLMFunctionJSON()
    obj.function.name = this.function_name
    obj.function.arguments = this.function_args
    return obj
  }
}

/** LLM 单轮响应：content 或 tool_calls 至少其一 */
export class LLMResponse {
  content: string = ''
  tool_calls: LLMToolCall[] = []
  finish_reason: string = ''

  get hasToolCalls(): boolean {
    return this.tool_calls.length > 0
  }
}

export interface LLMRequestOptions {
  baseUrl: string
  apiKey: string
  model: string
  messages: LLMChatMessage[]
  tools: LLMToolSpec[]
  timeoutMs: number
}

const TAG = 'LLMClient'

class LLMClientImpl {
  /** p10c: 最近一次 chat 失败的可读错误（成功路径清空），供设置页「测试连接」展示 */
  lastError: string = ''

  /** 把 baseUrl 归一化成完整 endpoint：{base}/v1/chat/completions（base 已含 /v1 时不重复加） */
  buildEndpoint(baseUrl: string): string {
    let base = baseUrl.trim()
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1)
    }
    if (base.endsWith('/v1')) {
      return base + '/chat/completions'
    }
    return base + '/v1/chat/completions'
  }

  /**
   * 发起一次 OpenAI 兼容 chat/completions 请求。
   * 返回 null 表示失败（错误已走 ErrorHandler）。
   */
  async chat(options: LLMRequestOptions): Promise<LLMResponse | null> {
    this.lastError = ''
    const endpoint = this.buildEndpoint(options.baseUrl)
    const body = new LLMRequestBody()
    body.model = options.model
    body.messages = options.messages.map(m => m.toJSON())
    if (options.tools.length > 0) {
      body.tools = options.tools.map(t => this.toolToJSON(t))
    }
    const bodyText = JSON.stringify(body)
    console.info(`[${TAG}] POST ${endpoint} model=${options.model} messages=${options.messages.length} tools=${options.tools.length} bodyBytes=${bodyText.length}`)

    const httpRequest = http.createHttp()
    try {
      const header: Record<string, string> = {
        'Content-Type': 'application/json'
      }
      if (options.apiKey.length > 0) {
        header['Authorization'] = `Bearer ${options.apiKey}`
      }
      const response = await httpRequest.request(endpoint, {
        method: http.RequestMethod.POST,
        header: header as Object,
        extraData: bodyText,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: options.timeoutMs,
        readTimeout: options.timeoutMs,
        usingCache: false
      })
      const statusCode = response.responseCode
      const resultText = `${response.result}`
      console.info(`[${TAG}] HTTP ${statusCode} len=${resultText.length}`)
      if (statusCode !== 200) {
        const snippet = resultText.length > 300 ? resultText.substring(0, 300) : resultText
        ErrorHandler.handle(new AppError(ErrorCodes.SYS_001,
          `LLM HTTP ${statusCode}: ${snippet}`))
        this.lastError = `HTTP ${statusCode}: ${snippet.substring(0, 120)}`
        return null
      }
      const parsed = this.parseResponse(resultText)
      if (!parsed) {
        ErrorHandler.handle(new AppError(ErrorCodes.SYS_001, 'LLM response parse failed'))
        this.lastError = '响应解析失败（非 OpenAI 兼容格式）'
        return null
      }
      return parsed
    } catch (e) {
      // P3 修复：完整异常详情（P2 终验发现 `${e}` 在 hilog 不可见——BusinessError 模板串接产 [object Object] 且可能被截断）
      // BusinessError 是 interface 不能 instanceof：属性探测 code 字段
      const be = e as BusinessError
      const detail = be.code !== undefined ? be.code + '/' + be.message : JSON.stringify(e)
      console.error(`[${TAG}] request exception: code=${be.code !== undefined ? be.code : 'N/A'} message=${detail}`)
      ErrorHandler.handle(new AppError(ErrorCodes.SYS_001, `LLM request failed: ${detail}`))
      this.lastError = `请求异常: ${detail.substring(0, 120)}`
      return null
    } finally {
      httpRequest.destroy()
    }
  }

  /** 工具定义转 OpenAI function 格式（parameters 经 toJSON 序列化） */
  toolToJSON(spec: LLMToolSpec): Record<string, Object> {
    const fn = new LLMToolFunctionJSON()
    fn.name = spec.name
    fn.description = spec.description
    fn.parameters = spec.parameters.toJSON()
    const tool = new LLMToolJSON()
    tool.function = fn
    const wrapper: Record<string, Object> = {}
    wrapper['type'] = tool.type
    wrapper['function'] = fn
    return wrapper
  }

  /** 解析 choices[0].message：content + tool_calls */
  parseResponse(responseText: string): LLMResponse | null {
    let root: Record<string, Object> | null = null
    try {
      root = JSON.parse(responseText) as Record<string, Object>
    } catch (e) {
      console.error(`[${TAG}] JSON.parse error: ${e}`)
      return null
    }
    if (!root) {
      return null
    }
    const choices = root['choices']
    if (!choices || !Array.isArray(choices) || choices.length === 0) {
      const errObj = root['error']
      if (errObj) {
        console.error(`[${TAG}] API error object: ${JSON.stringify(errObj)}`)
      }
      return null
    }
    const choice = choices[0] as Record<string, Object>
    const message = choice['message'] as Record<string, Object> | undefined
    const resp = new LLMResponse()
    if (choice['finish_reason'] !== undefined && choice['finish_reason'] !== null) {
      resp.finish_reason = `${choice['finish_reason']}`
    }
    if (message) {
      if (message['content'] !== undefined && message['content'] !== null) {
        resp.content = `${message['content']}`
      }
      const rawCalls = message['tool_calls']
      if (rawCalls && Array.isArray(rawCalls)) {
        for (const raw of rawCalls as Object[]) {
          const callObj = raw as Record<string, Object>
          const id = callObj['id'] !== undefined && callObj['id'] !== null ? `${callObj['id']}` : `call_${Date.now()}`
          let name = ''
          let args = '{}'
          const fnObj = callObj['function'] as Record<string, Object> | undefined
          if (fnObj) {
            if (fnObj['name'] !== undefined && fnObj['name'] !== null) {
              name = `${fnObj['name']}`
            }
            if (fnObj['arguments'] !== undefined && fnObj['arguments'] !== null) {
              args = `${fnObj['arguments']}`
            }
          }
          if (name.length > 0) {
            resp.tool_calls.push(new LLMToolCall(id, name, args))
          }
        }
      }
    }
    console.info(`[${TAG}] parsed: finish=${resp.finish_reason} contentLen=${resp.content.length} toolCalls=${resp.tool_calls.length}`)
    return resp
  }
}

export const LLMClient = new LLMClientImpl()
