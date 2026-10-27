/**
 * P51 (1c): 深度脱敏 —— 所有写入 SessionRecord/OperationLog/AuditLogger 的
 * 结构化内容先过 redactDeep()。
 *
 * 与 Redact.ets（浅层字符串）的关系：
 * - Redact.redact 处理自由文本（sk-/password=/token/hex16）；
 * - 本模块处理**键控敏感**：无论值长什么样，只要键名命中敏感模式即整体掩蔽；
 *   并对 type/fill/act 的 text 参数做 8 字符截断（动作可审计，内容不泄露）。
 */

/** 键名敏感模式：password/passwd/otp/secret/token/api_key/apiKey/card/卡号 */
const SENSITIVE_KEY_RE: RegExp = /(password|passwd|otp|secret|token|api_?key|card|credential|卡号|密码)/i
/** 值截断白名单：这些键的值保留前 8 字符 + *** */
const TRUNCATE_KEYS: string[] = ['text', 'value', 'fill', 'input']
const TRUNCATE_KEEP: number = 8

function maskValue(): string {
  return '***'
}

function truncateValue(v: string): string {
  if (v.length <= TRUNCATE_KEEP) {
    return v + '***'
  }
  return v.substring(0, TRUNCATE_KEEP) + '***'
}

function isSensitiveKey(key: string): boolean {
  return SENSITIVE_KEY_RE.test(key)
}

function isTruncateKey(key: string): boolean {
  const lower = key.toLowerCase()
  for (const t of TRUNCATE_KEYS) {
    if (lower === t || lower.endsWith('_' + t)) {
      return true
    }
  }
  return false
}

/**
 * 深度脱敏：递归处理对象/数组/字符串。
 * - 敏感键 → 值整体 ***（无论类型）
 * - type/fill/value/input 键（act 工具的 text 参数等）→ 前 8 字符 + ***
 * - 其余字符串原样保留（URL 等已有浅层 redact 兜底）
 */
export function redactDeep<T>(value: T): T {
  if (value === null || value === undefined) {
    return value
  }
  if (typeof value === 'string') {
    return value
  }
  if (Array.isArray(value)) {
    const out: Object[] = []
    for (const item of value as Object[]) {
      out.push(redactDeep(item) as Object)
    }
    return out as Object as T
  }
  if (typeof value === 'object') {
    const src = value as Record<string, Object>
    const out: Record<string, Object> = {}
    for (const k of Object.keys(src)) {
      const v = src[k]
      if (isSensitiveKey(k)) {
        out[k] = maskValue()
      } else if (isTruncateKey(k) && typeof v === 'string') {
        out[k] = truncateValue(v as string)
      } else {
        out[k] = redactDeep(v)
      }
    }
    return out as Object as T
  }
  return value
}

/**
 * 序列化 + 深脱敏（写审计日志入口用）。
 * 兜底：解析失败时退化为浅层字符串脱敏。
 */
export function redactDeepStringify(value: Object, shallowFallback: (s: string) => string): string {
  try {
    return JSON.stringify(redactDeep(value))
  } catch (e) {
    return shallowFallback(`${value}`)
  }
}
