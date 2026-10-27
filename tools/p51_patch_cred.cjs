// P51 part5: CredentialStore migration - Asset Store as primary source of truth
// Strategy:
//   - secrets (password field) live ONLY in Asset Store (alias browseros_pw_<id>)
//   - preferences keeps metadata only: id/domain/username/createdAt (NO password)
//   - one-shot migration: legacy prefs rows with plaintext password -> move secret to asset, strip password from prefs
//   - getAll() merges: metadata from prefs + secret fetched from asset (sync query)
const fs = require('fs')
const FILE = 'entry/src/main/ets/service/CredentialStore.ets'
let s = fs.readFileSync(FILE, 'utf8')
const D = s.includes('\r\n') ? '\r\n' : '\n'

function rep(o, n, tag) {
  const oo = o.split('\n').join(D), nn = n.split('\n').join(D)
  if (s.includes(nn)) { console.log('skip: ' + tag); return }
  if (!s.includes(oo)) { console.error('MISS: ' + tag); process.exit(1) }
  s = s.replace(oo, nn)
  console.log('ok: ' + tag)
}

// 1. header doc update
rep(' * P47-B: 密码管理器 —— 凭据存储服务\n * - Asset Store Kit (@ohos.security.asset) 加密镜像（尽力而为，失败回落 prefs）\n * - 主数据存 preferences（cred_store）\n * - Bitwarden JSON 明文导出格式导入/导出',
    ' * P47-B: 密码管理器 —— 凭据存储服务\n * P51 (1d): Asset Store 为主真值源 —— password 只存 asset（alias browseros_pw_<id>），\n * preferences 只留元数据（id/domain/username/createdAt）；init 时一次性把旧明文迁移到\n * asset 并从 prefs 抹除 password 字段。asset 不可用时维持旧行为（明文 prefs）并打日志。')

// 2. init: one-shot migration after prefs ready
rep("      this.prefs = p\n      // init 前若有内存写入（cache），补写落盘\n      if (this.cache !== null && this.cache.length > 0) {\n        this.persist(this.cache)\n      }\n      console.info('[P47] CredentialStore prefs ready')",
    "      this.prefs = p\n      // P51 (1d): 一次性迁移 —— prefs 里的明文 password 搬进 asset，prefs 只留元数据\n      this.migrateLegacyPlaintext()\n      // init 前若有内存写入（cache），补写落盘\n      if (this.cache !== null && this.cache.length > 0) {\n        this.persist(this.cache)\n      }\n      console.info('[P47] CredentialStore prefs ready (P51 asset-primary)')")

// 3. getAll: merge metadata (prefs) + secrets (asset)
rep("  getAll(): Credential[] {\n    if (this.cache !== null) {\n      return this.cache\n    }\n    let raw = '[]'\n    if (this.prefs) {\n      try {\n        raw = this.prefs.getSync('creds', '[]') as string\n      } catch (e) {\n        raw = '[]'\n      }\n    }\n    try {\n      const parsed = JSON.parse(raw) as object\n      const arr = Array.isArray(parsed) ? parsed as Credential[] : []\n      arr.sort((a: Credential, b: Credential): number => b.createdAt - a.createdAt)\n      this.cache = arr\n      return arr\n    } catch (e) {\n      this.cache = []\n      return []\n    }\n  }",
    "  getAll(): Credential[] {\n    if (this.cache !== null) {\n      return this.cache\n    }\n    let raw = '[]'\n    if (this.prefs) {\n      try {\n        raw = this.prefs.getSync('creds', '[]') as string\n      } catch (e) {\n        raw = '[]'\n      }\n    }\n    try {\n      const parsed = JSON.parse(raw) as object\n      const arr = Array.isArray(parsed) ? parsed as Credential[] : []\n      // P51 (1d): 元数据里 password 一律为空（真值在 asset）；asset 可用时回填密文取回的明文\n      if (this.assetOk()) {\n        for (const c of arr) {\n          const sec = this.assetGet(this.aliasOf(c.id))\n          c.password = sec === null ? '' : sec\n        }\n      }\n      arr.sort((a: Credential, b: Credential): number => b.createdAt - a.createdAt)\n      this.cache = arr\n      return arr\n    } catch (e) {\n      this.cache = []\n      return []\n    }\n  }")

// 4. persist: metadata only (strip password)
rep("  private persist(all: Credential[]): void {\n    this.cache = all\n    if (this.prefs) {\n      try {\n        this.prefs.putSync('creds', JSON.stringify(all))\n        this.prefs.flush()\n      } catch (e) {\n        console.error('[P47] persist fail')\n      }\n    }\n  }",
    "  private persist(all: Credential[]): void {\n    this.cache = all\n    if (this.prefs) {\n      try {\n        // P51 (1d): prefs 只落元数据，password 字段抹除（真值 = asset）\n        const meta: object[] = []\n        for (const c of all) {\n          meta.push({\n            id: c.id,\n            domain: c.domain,\n            username: c.username,\n            password: '',\n            createdAt: c.createdAt\n          } as object)\n        }\n        this.prefs.putSync('creds', JSON.stringify(meta))\n        this.prefs.flush()\n      } catch (e) {\n        console.error('[P47] persist fail')\n      }\n    }\n  }\n\n  /** P51 (1d): asset 可用且同步 API 正常 */\n  private assetOk(): boolean {\n    try {\n      const q: asset.AssetMap = new Map()\n      q.set(asset.Tag.ALIAS, this.strToU8('browseros_p51_probe'))\n      q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES)\n      asset.querySync(q)\n      return true\n    } catch (eA) {\n      const ea = eA as BusinessError\n      if (ea.code === 24000002) {\n        return true  // not found == service fine\n      }\n      return false\n    }\n  }\n\n  /** P51 (1d): 从 asset 取回明文（null = 无记录或服务不可用） */\n  private assetGet(alias: string): string | null {\n    try {\n      const q: asset.AssetMap = new Map()\n      q.set(asset.Tag.ALIAS, this.strToU8(alias))\n      q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)\n      const rows = asset.querySync(q)\n      if (rows.length === 0) {\n        return null\n      }\n      const secretU8 = rows[0].get(asset.Tag.SECRET)\n      if (!secretU8) {\n        return null\n      }\n      return this.u8ToStr(secretU8)\n    } catch (e) {\n      return null\n    }\n  }\n\n  private aliasOf(id: string): string {\n    return ALIAS_PREFIX + id\n  }\n\n  private u8ToStr(u8: Uint8Array): string {\n    let s = ''\n    for (let i = 0; i < u8.length; i++) {\n      s += String.fromCharCode(u8[i])\n    }\n    return s\n  }\n\n  /** P51 (1d): 一次性迁移 —— prefs 明文 password → asset，prefs 抹除 */\n  private migrateLegacyPlaintext(): void {\n    if (!this.prefs || !this.assetOk()) {\n      console.warn('[P51] credential migration skipped (prefs or asset unavailable)')\n      return\n    }\n    let raw = '[]'\n    try {\n      raw = this.prefs.getSync('creds', '[]') as string\n    } catch (e) {\n      return\n    }\n    let arr: Credential[] = []\n    try {\n      const parsed = JSON.parse(raw) as object\n      arr = Array.isArray(parsed) ? parsed as Credential[] : []\n    } catch (e) {\n      return\n    }\n    let migrated = 0\n    for (const c of arr) {\n      if (c.password && c.password.length > 0) {\n        // 明文在 prefs → 搬进 asset\n        this.assetMirror(c)\n        migrated++\n      }\n    }\n    if (migrated > 0) {\n      // 重写 prefs：password 全部抹除\n      const meta: object[] = []\n      for (const c of arr) {\n        meta.push({\n          id: c.id,\n          domain: c.domain,\n          username: c.username,\n          password: '',\n          createdAt: c.createdAt\n        } as object)\n      }\n      try {\n        this.prefs.putSync('creds', JSON.stringify(meta))\n        this.prefs.flush()\n      } catch (e) {\n        console.error('[P51] migration prefs rewrite fail')\n        return\n      }\n      console.info('[P51] credential migration done: ' + migrated + ' secrets moved to asset, prefs stripped')\n    } else {\n      console.info('[P51] credential migration: no legacy plaintext found')\n    }\n  }")

fs.writeFileSync(FILE, s, 'utf8')
console.log('part5 done')
