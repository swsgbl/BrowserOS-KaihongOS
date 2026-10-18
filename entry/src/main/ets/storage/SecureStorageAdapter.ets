import { asset } from '@kit.AssetStoreKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { StorageManager } from './StorageManager'

/**
 * P36: 真加密安全存储适配器 —— 底层换成 @ohos.security.asset（AssetStoreKit）。
 *
 * - 新秘密一律走 asset kv（putSecret/getSecret/removeSecret），由系统服务
 *   在安全存储区加密落盘，应用沙箱内不再出现任何密钥文件。
 * - 旧接口（encryptStore/decryptLoad 等）保留为 legacy 兼容层：
 *   P14b 时代写入的 XOR 伪加密 login_state 档案仍可读（只读路径），
 *   但新写入不再经过它们（LoginStateManager P36 改为 asset 可用时跳过文件副本）。
 * - asset 服务不可用（错误码 24000001 等）时进入降级模式：
 *   isSecureStorageAvailable()=false，密钥留在 config.json 原行为不变，
 *   并打 [P36] asset unavailable 警告（一次性，init 时）。
 */
const LEGACY_XOR_KEY = 'browseros_kaihongos_2026'
const B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
const MAX_SECRET_LEN = 1024 * 1024

/** P36: asset 探测别名（不落 SECRET，仅 query 探活） */
const ALIAS_PROBE = 'browseros_p36_probe'

class SecureStorageAdapterImpl {
  private assetAvailable: boolean = false
  private initDone: boolean = false
  private encoder: util.TextEncoder = new util.TextEncoder()
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8')

  /**
   * P36: 启动探测 asset 服务。query 一个不存在的探测别名：
   * 抛 24000002(not found) 说明服务活着；其它错误码视为不可用。
   * 幂等（initDone 守卫），由 ConfigManager.load 前 await。
   */
  async init(): Promise<void> {
    if (this.initDone) {
      return
    }
    const t0 = Date.now()
    try {
      const q: asset.AssetMap = new Map()
      q.set(asset.Tag.ALIAS, this.encoder.encodeInto(ALIAS_PROBE))
      q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES)
      await asset.query(q)
      this.assetAvailable = true
    } catch (e) {
      const err = e as BusinessError
      if (err.code === 24000002) {
        // not found == 服务在、条目不存在 —— 探活成功
        this.assetAvailable = true
      } else {
        this.assetAvailable = false
        console.warn(`[P36] asset unavailable: code=${err.code} msg=${err.message} (fallback to plaintext mode)`)
      }
    }
    this.initDone = true
    console.info(`[P36] SecureStorageAdapter init: asset=${this.assetAvailable} probe_ms=${Date.now() - t0}`)
  }

  isSecureStorageAvailable(): boolean {
    return this.assetAvailable
  }

  /** P36: 写入/覆盖一条秘密（asset.add，已存在则 asset.update） */
  async putSecret(alias: string, secret: string): Promise<boolean> {
    if (!this.assetAvailable || secret.length === 0 || secret.length > MAX_SECRET_LEN) {
      return false
    }
    const attrs: asset.AssetMap = new Map()
    attrs.set(asset.Tag.ALIAS, this.encoder.encodeInto(alias))
    attrs.set(asset.Tag.SECRET, this.encoder.encodeInto(secret))
    try {
      await asset.add(attrs)
      return true
    } catch (eAdd) {
      const ea = eAdd as BusinessError
      if (ea.code !== 24000003) {
        // 24000003 = already exists → 走 update；其它错误上抛统一记
        console.warn(`[P36] asset add fail ${alias}: code=${ea.code}`)
        return false
      }
    }
    try {
      // update: query={ALIAS}, 更新体只含 SECRET（ALIAS 不可变更，携带会 401）
      const updQuery: asset.AssetMap = new Map()
      updQuery.set(asset.Tag.ALIAS, this.encoder.encodeInto(alias))
      const updAttrs: asset.AssetMap = new Map()
      updAttrs.set(asset.Tag.SECRET, this.encoder.encodeInto(secret))
      await asset.update(updQuery, updAttrs)
      return true
    } catch (eUpd) {
      const eu = eUpd as BusinessError
      console.warn(`[P36] asset update fail ${alias}: code=${eu.code}`)
      return false
    }
  }

  /** P36: 读取一条秘密（query RETURN_TYPE=ALL），不存在返回 null */
  async getSecret(alias: string): Promise<string | null> {
    if (!this.assetAvailable) {
      return null
    }
    try {
      const q: asset.AssetMap = new Map()
      q.set(asset.Tag.ALIAS, this.encoder.encodeInto(alias))
      q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
      const res: Array<asset.AssetMap> = await asset.query(q)
      if (res.length === 0) {
        return null
      }
      const secret: asset.Value | undefined = res[0].get(asset.Tag.SECRET)
      if (secret instanceof Uint8Array) {
        return this.decoder.decodeToString(secret)
      }
      return null
    } catch (e) {
      const err = e as BusinessError
      if (err.code !== 24000002) {
        console.warn(`[P36] asset query fail ${alias}: code=${err.code}`)
      }
      return null
    }
  }

  /** P36: 删除一条秘密（不存在视为成功） */
  async removeSecret(alias: string): Promise<boolean> {
    if (!this.assetAvailable) {
      return false
    }
    try {
      const q: asset.AssetMap = new Map()
      q.set(asset.Tag.ALIAS, this.encoder.encodeInto(alias))
      await asset.remove(q)
      return true
    } catch (e) {
      const err = e as BusinessError
      if (err.code === 24000002) {
        return true
      }
      console.warn(`[P36] asset remove fail ${alias}: code=${err.code}`)
      return false
    }
  }

  // ---------------- legacy 文件兼容层（只读解密 + 明文降级写） ----------------

  /**
   * P36 legacy: 新代码勿用。asset 不可用时的明文文件降级写
   * （与旧行为 huksAvailable=false 分支一致）。
   */
  async encryptStore(relativePath: string, data: string): Promise<boolean> {
    if (this.assetAvailable) {
      // asset 模式下不应再有秘密落到文件 —— 防御性拒绝并留痕
      console.warn('[P36] encryptStore rejected in asset mode: ' + relativePath)
      return false
    }
    return StorageManager.save(relativePath, data)
  }

  /**
   * P36 legacy: 读历史 login_state 档案。尝试旧 XOR 解码，
   * 解出 JSON 形态（{ 或 [ 开头）用之；否则按明文原文返回
   * （P14b 实际落盘多为明文 —— 旧 init 从未被调用，huksAvailable 恒 false）。
   */
  async decryptLoad(relativePath: string): Promise<string | null> {
    const data = await StorageManager.load(relativePath)
    if (!data) {
      return null
    }
    const decoded = this.legacyXorDecrypt(data)
    if (decoded !== null && decoded.length > 0 &&
      (decoded.charAt(0) === '{' || decoded.charAt(0) === '[')) {
      return decoded
    }
    return data
  }

  async encryptStoreJSON(relativePath: string, data: Object): Promise<boolean> {
    return this.encryptStore(relativePath, JSON.stringify(data))
  }

  async decryptLoadJSON(relativePath: string): Promise<Record<string, Object> | null> {
    const content = await this.decryptLoad(relativePath)
    if (content) {
      try {
        return JSON.parse(content) as Record<string, Object>
      } catch (e) {
        return null
      }
    }
    return null
  }

  /** P36 legacy: 旧 XOR+base64 解码（仅用于读历史档案，不再用于任何新写入） */
  private legacyXorDecrypt(data: string): string | null {
    try {
      const decoded = this.base64Decode(data)
      let result = ''
      for (let i = 0; i < decoded.length; i++) {
        const charCode = decoded.charCodeAt(i) ^ LEGACY_XOR_KEY.charCodeAt(i % LEGACY_XOR_KEY.length)
        result += String.fromCharCode(charCode)
      }
      return result
    } catch (e) {
      return null
    }
  }

  private base64Decode(str: string): string {
    let result = ''
    let i = 0
    while (i < str.length) {
      const a = B64_CHARS.indexOf(str.charAt(i++))
      const b = B64_CHARS.indexOf(str.charAt(i++))
      const c = B64_CHARS.indexOf(str.charAt(i++))
      const d = B64_CHARS.indexOf(str.charAt(i++))
      const triplet = (a << 18) | (b << 12) | ((c !== -1 ? c : 0) << 6) | (d !== -1 ? d : 0)
      result += String.fromCharCode((triplet >> 16) & 0xFF)
      if (c !== -1) {
        result += String.fromCharCode((triplet >> 8) & 0xFF)
      }
      if (d !== -1) {
        result += String.fromCharCode(triplet & 0xFF)
      }
    }
    return result
  }
}

export const SecureStorageAdapter = new SecureStorageAdapterImpl()
