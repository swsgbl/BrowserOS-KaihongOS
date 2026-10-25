/**
 * P42 (KAI-075): 敏感信息脱敏工具。
 * 模式清单（brief 定义）：
 *   - sk-[A-Za-z0-9]{8,}           API key 风格
 *   - password=...                 密码赋值
 *   - "token":"..."                JSON token 字段
 *   - 连续 16+ 十六进制字符          密钥指纹风格
 * 防误伤：data:image/...;base64 段（截图 dataUrl）先挖洞保护，脱敏后原样还原。
 */
export class Redact {
  private static readonly RE_IMAGE_DATA: RegExp = /data:image\/[a-zA-Z+]+;base64,[A-Za-z0-9+/=]+/g
  private static readonly RE_SK: RegExp = /sk-[A-Za-z0-9]{8,}/g
  private static readonly RE_PASSWORD: RegExp = /password=[^\s&"'<>]{1,128}/gi
  private static readonly RE_TOKEN_JSON: RegExp = /("token"\s*:\s*")[^"]{1,256}(")/g
  private static readonly RE_HEX16: RegExp = /[0-9a-fA-F]{16,}/g

  static redact(s: string): string {
    if (!s || s.length === 0) {
      return s
    }
    // 挖洞：图片 dataUrl 不是敏感信息，且 base64 含大量 hex 字符会被 16+hex 模式误伤
    const holes: string[] = []
    const holeRe = new RegExp(Redact.RE_IMAGE_DATA.source, 'g')
    let out = s.replace(holeRe, (m: string): string => {
      holes.push(m)
      return `\u0000H${holes.length - 1}\u0000`
    })
    out = out.replace(new RegExp(Redact.RE_SK.source, 'g'), '***')
    out = out.replace(new RegExp(Redact.RE_PASSWORD.source, 'gi'), '***')
    out = out.replace(new RegExp(Redact.RE_TOKEN_JSON.source, 'g'), '$1***$2')
    out = out.replace(new RegExp(Redact.RE_HEX16.source, 'g'), '***')
    out = out.replace(/\u0000H(\d+)\u0000/g, (_m: string, i: string): string => {
      const idx = parseInt(i, 10)
      return idx >= 0 && idx < holes.length ? holes[idx] : ''
    })
    return out
  }
}

/** 便捷函数：MCP 工具响应序列化与 AuditLogger 写入处统一调用 */
export function redactSensitive(s: string): string {
  return Redact.redact(s)
}
