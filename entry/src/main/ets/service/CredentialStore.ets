/**
 * P47-B: 密码管理器 —— 凭据存储服务
 * - Asset Store Kit (@ohos.security.asset) 加密镜像（尽力而为，失败回落 prefs）
 * - 主数据存 preferences（cred_store）
 * - Bitwarden JSON 明文导出格式导入/导出
 * 采用模块级单例（项目惯例，避开 arkts-no-standalone-this）
 */
import { asset } from '@kit.AssetStoreKit'
import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'

export interface Credential {
  id: string
  domain: string
  username: string
  password: string
  createdAt: number
}

const ALIAS_PREFIX = 'browseros_pw_'

class CredentialStoreImpl {
  private prefs: preferences.Preferences | null = null
  private cache: Credential[] | null = null
  private readyPromise: Promise<void> = Promise.resolve()

  init(ctx: Context): void {
    this.readyPromise = preferences.getPreferences(ctx, { name: 'cred_store' }).then((p: preferences.Preferences): void => {
      this.prefs = p
      // init 前若有内存写入（cache），补写落盘
      if (this.cache !== null && this.cache.length > 0) {
        this.persist(this.cache)
      }
      console.info('[P47] CredentialStore prefs ready')
    }).catch((e: Object): void => {
      console.error('[P47] CredentialStore init fail: ' + e)
    })
  }

  ready(): Promise<void> {
    return this.readyPromise
  }

  getAll(): Credential[] {
    if (this.cache !== null) {
      return this.cache
    }
    let raw = '[]'
    if (this.prefs) {
      try {
        raw = this.prefs.getSync('creds', '[]') as string
      } catch (e) {
        raw = '[]'
      }
    }
    try {
      const parsed = JSON.parse(raw) as object
      const arr = Array.isArray(parsed) ? parsed as Credential[] : []
      arr.sort((a: Credential, b: Credential): number => b.createdAt - a.createdAt)
      this.cache = arr
      return arr
    } catch (e) {
      this.cache = []
      return []
    }
  }

  getByDomain(domain: string): Credential[] {
    const out: Credential[] = []
    for (const c of this.getAll()) {
      if (c.domain === domain) {
        out.push(c)
      }
    }
    return out
  }

  hasCredentialFor(domain: string): boolean {
    return this.getByDomain(domain).length > 0
  }

  add(domain: string, username: string, password: string): void {
    const cred: Credential = {
      id: 'pw_' + Date.now() + '_' + Math.floor(Math.random() * 1000),
      domain: domain,
      username: username,
      password: password,
      createdAt: Date.now()
    }
    const all = this.getAll().slice()
    let replaced = false
    for (let i = 0; i < all.length; i++) {
      if (all[i].domain === domain && all[i].username === username) {
        cred.id = all[i].id
        cred.createdAt = all[i].createdAt
        all[i] = cred
        replaced = true
        break
      }
    }
    if (!replaced) {
      all.push(cred)
    }
    this.persist(all)
    this.assetMirror(cred)
  }

  update(id: string, domain: string, username: string, password: string): void {
    const all = this.getAll().slice()
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === id) {
        const upd: Credential = {
          id: id,
          domain: domain,
          username: username,
          password: password,
          createdAt: all[i].createdAt
        }
        all[i] = upd
        this.persist(all)
        this.assetMirror(upd)
        break
      }
    }
  }

  remove(id: string): void {
    const all: Credential[] = []
    for (const c of this.getAll()) {
      if (c.id !== id) {
        all.push(c)
      }
    }
    this.persist(all)
    this.assetRemove(ALIAS_PREFIX + id)
  }

  clearAll(): void {
    for (const c of this.getAll()) {
      this.assetRemove(ALIAS_PREFIX + c.id)
    }
    this.cache = []
    if (this.prefs) {
      try {
        this.prefs.putSync('creds', '[]')
        this.prefs.flush()
      } catch (e) {
        console.error('[P47] clearAll flush fail')
      }
    }
  }

  /** Bitwarden 明文 JSON 导入。返回导入条数；-1 = 格式不符。 */
  importBitwardenJson(jsonText: string): number {
    let obj: object | null = null
    try {
      obj = JSON.parse(jsonText) as object
    } catch (e) {
      return -1
    }
    if (!obj) {
      return -1
    }
    const root = obj as Record<string, object>
    const itemsVal = root['items']
    if (!itemsVal || !Array.isArray(itemsVal)) {
      return -1
    }
    const items = itemsVal as object[]
    let n = 0
    for (const it of items) {
      const item = it as Record<string, object>
      const loginVal = item['login']
      if (!loginVal) {
        continue
      }
      const login = loginVal as Record<string, object>
      const username = this.asStr(login['username'])
      const password = this.asStr(login['password'])
      let domain = ''
      const urisVal = login['uris']
      if (urisVal && Array.isArray(urisVal) && (urisVal as object[]).length > 0) {
        const first = (urisVal as Record<string, object>[])[0]
        const u = this.asStr(first['uri'])
        const m = u.match(/^https?:\/\/([^\/?#]+)/)
        domain = m && m.length > 1 ? m[1] : u
      }
      if (domain.length === 0) {
        domain = this.asStr(item['name'])
      }
      if (domain.length === 0) {
        domain = 'unknown'
      }
      if (username.length === 0 && password.length === 0) {
        continue
      }
      this.add(domain, username, password)
      n++
    }
    console.info('[P47] bitwarden import: ' + n + ' items')
    return n
  }

  /** 导出为 Bitwarden 兼容 JSON（明文，字符串手工拼装避开 arkts-no-untyped-obj-literals） */
  exportBitwardenJson(): string {
    let s = '{"encrypted":false,"items":['
    let first = true
    for (const c of this.getAll()) {
      if (!first) {
        s += ','
      }
      first = false
      s += '{"name":' + JSON.stringify(c.domain)
      s += ',"login":{"username":' + JSON.stringify(c.username)
      s += ',"password":' + JSON.stringify(c.password)
      s += ',"uris":[{"uri":"https://' + c.domain + '"}]}}'
    }
    s += ']}'
    return s
  }

  private asStr(v: object | undefined): string {
    return typeof v === 'string' ? v : ''
  }

  private persist(all: Credential[]): void {
    this.cache = all
    if (this.prefs) {
      try {
        this.prefs.putSync('creds', JSON.stringify(all))
        this.prefs.flush()
      } catch (e) {
        console.error('[P47] persist fail')
      }
    }
  }

  /** 单条凭据写入 Asset Store（系统级加密，尽力而为） */
  private assetMirror(c: Credential): void {
    try {
      const attrs: asset.AssetMap = new Map()
      attrs.set(asset.Tag.SECRET, this.strToU8(JSON.stringify(c)))
      attrs.set(asset.Tag.ALIAS, this.strToU8(ALIAS_PREFIX + c.id))
      attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED)
      try {
        asset.removeSync(this.assetQueryOf(ALIAS_PREFIX + c.id))
      } catch (e) {
        // not exist yet
      }
      asset.addSync(attrs)
      console.info('[P47] asset mirrored: ' + c.id)
    } catch (e) {
      console.warn('[P47] asset mirror fail (fallback prefs only): ' + e)
    }
  }

  private assetRemove(alias: string): void {
    try {
      asset.removeSync(this.assetQueryOf(alias))
    } catch (e) {
      // ignore
    }
  }

  private assetQueryOf(alias: string): asset.AssetMap {
    const q: asset.AssetMap = new Map()
    q.set(asset.Tag.ALIAS, this.strToU8(alias))
    return q
  }

  private strToU8(s: string): Uint8Array {
    const ret = new Uint8Array(s.length)
    for (let i = 0; i < s.length; i++) {
      ret[i] = s.charCodeAt(i) & 0xFF
    }
    return ret
  }
}

export const CredentialStore = new CredentialStoreImpl()
