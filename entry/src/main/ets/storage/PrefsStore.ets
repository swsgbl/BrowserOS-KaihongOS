/**
 * P14b/c: 登录态与会话元数据的 Preferences 载体封装
 *
 * 【载体决策记录】Preferences 单 Value 上限 16MB：
 * - login_state: 键 login_token(string)、session_info(JSON string)。
 *   Token/会话信息实际远小于 16MB，但防御性处理：超限降级截断 + hilog 警告。
 * - sessions_meta: 键 session_index(sessionId 数组 JSON)。
 *   会话详情（截图 base64/操作日志大对象）仍留 files/sessions/*.json 文件，
 *   避免单值超 16MB 风险 —— 元数据走 Preferences、大对象走文件的双层结构。
 *
 * ArkTS 严格；API≤14（preferences since9，getPreferences(context,name) Promise 形态）。
 */
import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'

/** Preferences 单 Value 上限（字节） */
export const PREFS_VALUE_MAX_BYTES: number = 16 * 1024 * 1024

class PrefsStoreImpl {
  private loginPrefs: preferences.Preferences | null = null
  private sessionsPrefs: preferences.Preferences | null = null

  /** EntryAbility 启动调用；幂等 */
  async init(context: Context): Promise<void> {
    if (this.loginPrefs === null) {
      try {
        this.loginPrefs = await preferences.getPreferences(context, 'login_state')
      } catch (e) {
        console.error('[PrefsStore] login_state init failed: ' + e)
      }
    }
    if (this.sessionsPrefs === null) {
      try {
        this.sessionsPrefs = await preferences.getPreferences(context, 'sessions_meta')
      } catch (e) {
        console.error('[PrefsStore] sessions_meta init failed: ' + e)
      }
    }
  }

  private storeOf(name: 'login_state' | 'sessions_meta'): preferences.Preferences | null {
    return name === 'login_state' ? this.loginPrefs : this.sessionsPrefs
  }

  /** 写 string 值并 flush。超 16MB 降级截断 + 警告返回 false */
  async putString(name: 'login_state' | 'sessions_meta', key: string, value: string): Promise<boolean> {
    const p = this.storeOf(name)
    if (!p) {
      return false
    }
    try {
      if (value.length > PREFS_VALUE_MAX_BYTES) {
        // 单 Value 上限 16MB：降级截断（写入前段），hilog 警告
        console.error(`[PrefsStore] value exceeds 16MB limit (len=${value.length}, key=${key}), truncated`)
        value = value.substring(0, PREFS_VALUE_MAX_BYTES)
      }
      await p.put(key, value)
      await p.flush()
      return true
    } catch (e) {
      console.error(`[PrefsStore] putString failed key=${key}: ` + e)
      return false
    }
  }

  async getString(name: 'login_state' | 'sessions_meta', key: string, def: string = ''): Promise<string> {
    const p = this.storeOf(name)
    if (!p) {
      return def
    }
    try {
      const v = await p.get(key, def)
      return typeof v === 'string' ? v : def
    } catch (e) {
      return def
    }
  }

  /** 读 JSON 值（内部 parse，失败返回 null） */
  async getJSON(name: 'login_state' | 'sessions_meta', key: string): Promise<Record<string, Object> | null> {
    const raw = await this.getString(name, key)
    if (raw.length === 0) {
      return null
    }
    try {
      return JSON.parse(raw) as Record<string, Object>
    } catch (e) {
      console.error(`[PrefsStore] getJSON parse failed key=${key}`)
      return null
    }
  }

  async remove(name: 'login_state' | 'sessions_meta', key: string): Promise<boolean> {
    const p = this.storeOf(name)
    if (!p) {
      return false
    }
    try {
      await p.delete(key)
      await p.flush()
      return true
    } catch (e) {
      return false
    }
  }

  async clear(name: 'login_state' | 'sessions_meta'): Promise<boolean> {
    const p = this.storeOf(name)
    if (!p) {
      return false
    }
    try {
      await p.clear()
      await p.flush()
      return true
    } catch (e) {
      return false
    }
  }
}

export const PrefsStore = new PrefsStoreImpl()
