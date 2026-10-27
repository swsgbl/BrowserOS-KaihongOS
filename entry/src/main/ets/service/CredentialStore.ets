/**
 * P47-B: 密码管理器 —— 凭据存储服务
 * P51 (1d): Asset Store 为主真值源 —— password 只存 asset（alias browseros_pw_<id>），
 * preferences 只留元数据（id/domain/username/createdAt）；init 时一次性把旧明文迁移到
 * asset 并从 prefs 抹除 password 字段。asset 不可用时维持旧行为（明文 prefs）并打日志。
 * 采用模块级单例（项目惯例，避开 arkts-no-standalone-this）
 */
import { asset } from '@kit.AssetStoreKit'
import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'

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
      // P51 (1d): 一次性迁移 —— prefs 里的明文 password 搬进 asset，prefs 只留元数据
      this.migrateLegacyPlaintext()
      // init 前若有内存写入（cache），补写落盘
      if (this.cache !== null && this.cache.length > 0) {
        this.persist(this.cache)
      }
      console.info('[P47] CredentialStore prefs ready (P51 asset-primary)')
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
      // P51 (1d): 元数据里 password 一律为空（真值在 asset）；asset 可用时回填密文取回的明文
      if (this.assetOk()) {
        for (const c of arr) {
          const sec = this.assetGet(this.aliasOf(c.id))
          c.password = sec === null ? '' : sec
        }
      }
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
        // P51 (1d): prefs 只落元数据，password 字段抹除（真值 = asset）
        const meta: Credential[] = []
        for (const c of all) {
          const m: Credential = {
            id: c.id,
            domain: c.domain,
            username: c.username,
            password: '',
            createdAt: c.createdAt
          }
          meta.push(m)
        }
        this.prefs.putSync('creds', JSON.stringify(meta))
        this.prefs.flush()
      } catch (e) {
        console.error('[P47] persist fail')
      }
    }
  }

  /** P51 (1d): asset 可用且同步 API 正常 */
  private assetOk(): boolean {
    try {
      const q: asset.AssetMap = new Map()
      q.set(asset.Tag.ALIAS, this.strToU8('browseros_p51_probe'))
      q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES)
      asset.querySync(q)
      return true
    } catch (eA) {
      const ea = eA as BusinessError
      if (ea.code === 24000002) {
        return true  // not found == service fine
      }
      return false
    }
  }

  /** P51 (1d): 从 asset 取回明文（null = 无记录或服务不可用） */
  private assetGet(alias: string): string | null {
    try {
      const q: asset.AssetMap = new Map()
      q.set(asset.Tag.ALIAS, this.strToU8(alias))
      q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
      const rows = asset.querySync(q)
      if (rows.length === 0) {
        return null
      }
      const secretVal = rows[0].get(asset.Tag.SECRET)
      if (!secretVal || typeof secretVal === 'number' || typeof secretVal === 'boolean') {
        return null
      }
      const secretU8: Uint8Array = secretVal
      if (!secretU8) {
        return null
      }
      return this.u8ToStr(secretU8)
    } catch (e) {
      return null
    }
  }

  private aliasOf(id: string): string {
    return ALIAS_PREFIX + id
  }

  private u8ToStr(u8: Uint8Array): string {
    let s = ''
    for (let i = 0; i < u8.length; i++) {
      s += String.fromCharCode(u8[i])
    }
    return s
  }

  /** P51 (1d): 一次性迁移 —— prefs 明文 password → asset，prefs 抹除 */
  private migrateLegacyPlaintext(): void {
    if (!this.prefs || !this.assetOk()) {
      console.warn('[P51] credential migration skipped (prefs or asset unavailable)')
      return
    }
    let raw = '[]'
    try {
      raw = this.prefs.getSync('creds', '[]') as string
    } catch (e) {
      return
    }
    let arr: Credential[] = []
    try {
      const parsed = JSON.parse(raw) as object
      arr = Array.isArray(parsed) ? parsed as Credential[] : []
    } catch (e) {
      return
    }
    let migrated = 0
    for (const c of arr) {
      if (c.password && c.password.length > 0) {
        // 明文在 prefs → 搬进 asset
        this.assetMirror(c)
        migrated++
      }
    }
    if (migrated > 0) {
      // 重写 prefs：password 全部抹除
      const meta: Credential[] = []
      for (const c of arr) {
        const m: Credential = {
          id: c.id,
          domain: c.domain,
          username: c.username,
          password: '',
          createdAt: c.createdAt
        }
        meta.push(m)
      }
      try {
        this.prefs.putSync('creds', JSON.stringify(meta))
        this.prefs.flush()
      } catch (e) {
        console.error('[P51] migration prefs rewrite fail')
        return
      }
      console.info('[P51] credential migration done: ' + migrated + ' secrets moved to asset, prefs stripped')
    } else {
      console.info('[P51] credential migration: no legacy plaintext found')
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
