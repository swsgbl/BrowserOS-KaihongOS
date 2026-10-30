/**
 * P69: 应用内更新服务 —— 后台下载 + 重启即更 + 国内外双源。
 *
 * 用户需求：更新像常见软件一样后台下载完提醒重启更新即可，不跳下载页；
 * 国内用户走国内仓库（AtomGit），国外用户走国外仓库（GitHub）。
 *
 * 设计（Zodex 已定，任务书 .zcode/p69_brief.md）：
 * - 检查：启动后 24h 节流自动查 + 关于页「检查更新」手动查（手动不受节流）。
 * - geo 策略 = 双源竞速（不做 IP 判定）：manifest 双 URL 5s 超时先到先用；
 *   设置项「更新源：自动(=竞速)/国内/国际」持久化覆盖。
 * - 下载：@ohos.net.http requestInStream 流式下到 files/updates/<ver>.hap
 *   （与 P16 DownloadManager 同款机制；更新包不入下载列表，进度走 EventBus）。
 * - 校验：下载完 sha256（cryptoFramework 摘要）对 manifest；失败自动换下一 URL
 *   源重下（cn+global 全试）。校验不得跳过。
 * - 应用（重启即更）：
 *   路径 A（有驻留 runner，P67 收件箱）：投递 kind=system_update 任务（prompt 携带
 *   hap 沙盒路径+sha256），runner(root) 执行 bm install -r <hap> && aa start → 重启即新版。
 *   路径 B（无 runner 常规设备）：如实文案「已下载至 files/updates（安装需应用市场或
 *   开发者工具）」——普通应用无自安装权限（诚实原则，禁止假安装）。
 * - 安全：全程 https；manifest 拉取失败静默（自动查不打扰）；成功安装后清理旧包。
 */
import http from '@ohos.net.http'
import fs from '@ohos.file.fs'
import cryptoFramework from '@ohos.security.cryptoFramework'
import { bundleManager } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { DeviceAgentStore } from './DeviceAgentStore'

export enum UpdatePhase {
  IDLE = 'idle',
  CHECKING = 'checking',
  AVAILABLE = 'available',   // 发现新版本（未开始下）
  DOWNLOADING = 'downloading',
  VERIFYING = 'verifying',
  READY = 'ready',           // 下载+校验完成，可重启更新
  INSTALLING = 'installing', // 已投递 runner，等待 bm install 结果
  UPTODATE = 'uptodate',
  FAILED = 'failed'
}

export class UpdateManifest {
  versionCode: number = 0
  versionName: string = ''
  sha256: string = ''
  size: number = 0
  notes: string = ''
  minCompatibleApi: number = 0
  globalUrls: string[] = []
  cnUrls: string[] = []
  sourceUrl: string = '' // manifest 本身来自哪个源（诊断用）
}

export class UpdateState {
  phase: UpdatePhase = UpdatePhase.IDLE
  manifest: UpdateManifest | null = null
  receivedBytes: number = 0
  totalBytes: number = 0
  progress: number = 0 // 0-100
  attemptUrl: string = ''
  error: string = ''
  readyPath: string = ''
}

/** 更新源偏好（config.json updateSourcePref） */
export type UpdateSourcePref = 'auto' | 'cn' | 'global'

// P69-fix(Zodex 实测): AtomGit /raw 是 SPA 壳不可直读(5792B HTML)；ghfast.top 前置 GitHub raw 在 VM 实测 200/真 JSON。
// CN 链 = ghfast->github raw（国内可达）；AtomGit raw 留作后续其开放 raw 时的第二候选（当前必败，竞速自然跳过）。
const MANIFEST_CN_URL = 'https://ghfast.top/https://raw.githubusercontent.com/swsgbl/BrowserOS-KaihongOS/main/update-manifest.json'
const MANIFEST_GLOBAL_URL = 'https://github.com/swsgbl/BrowserOS-KaihongOS/releases/latest/download/update-manifest.json'
const STATE_PATH = 'update_state.json'
const UPDATES_DIR = 'updates'
const THROTTLE_MS = 24 * 60 * 60 * 1000 // 24h 自动查节流
const MANIFEST_TIMEOUT_MS = 5000 // 双源竞速 5s 超时先到先用
const DOWNLOAD_TIMEOUT_MS = 120000

function now(): number {
  return new Date().getTime()
}

class UpdateServiceImpl {
  private state: UpdateState = new UpdateState()
  private pref: UpdateSourcePref = 'auto'
  private dir: string = ''
  private lastAutoCheck: number = 0
  private httpReq: http.HttpRequest | null = null
  private downloading: boolean = false

  /** EntryAbility 启动链挂接：恢复节流时间戳，触发 24h 节流自动查 */
  init(filesDir: string, pref: UpdateSourcePref): void {
    this.dir = filesDir + '/' + UPDATES_DIR
    this.pref = pref
    try {
      if (!fs.accessSync(this.dir)) {
        fs.mkdirSync(this.dir, true)
      }
    } catch (e) {
      console.error('[P69] mkdir updates dir error: ' + e)
    }
    const rec = StorageManager.getSync(STATE_PATH)
    if (rec !== null) {
      this.lastAutoCheck = rec.lastAutoCheck as number
    }
    console.info(`[P69] init dir=${this.dir} pref=${this.pref} lastAutoCheck=${this.lastAutoCheck}`)
  }

  setPref(pref: UpdateSourcePref): void {
    this.pref = pref
    console.info('[P69] source pref -> ' + pref)
  }

  getState(): UpdateState {
    return this.state
  }

  /** 启动自动查（24h 节流；失败静默） */
  autoCheck(): void {
    const t = now()
    if (t - this.lastAutoCheck < THROTTLE_MS) {
      console.info('[P69] autoCheck throttled (last ' + Math.floor((t - this.lastAutoCheck) / 3600000) + 'h ago)')
      return
    }
    this.lastAutoCheck = t
    this.persistState()
    this.checkForUpdate(false).then(() => {
    }).catch((e: BusinessError) => {
      console.info('[P69] autoCheck silent fail: ' + e.message) // 静默
    })
  }

  /** 手动/自动检查。force=true 绕过节流（关于页按钮）。返回是否发现新版本 */
  async checkForUpdate(force: boolean): Promise<boolean> {
    this.state = new UpdateState()
    this.state.phase = UpdatePhase.CHECKING
    this.emit()
    console.info(`[P69] checkForUpdate force=${force} pref=${this.pref}`)
    const m = await this.fetchManifest()
    if (m === null) {
      this.state.phase = UpdatePhase.UPTODATE
      this.state.error = 'manifest unreachable'
      this.emit()
      return false
    }
    const cur = this.currentVersionCode()
    console.info(`[P69] manifest ${m.versionName}(code=${m.versionCode}) via ${m.sourceUrl} vs current code=${cur}`)
    if (m.versionCode <= cur) {
      this.state.phase = UpdatePhase.UPTODATE
      this.emit()
      return false
    }
    this.state.manifest = m
    this.state.phase = UpdatePhase.AVAILABLE
    this.emit()
    // 发现新版本 → 自动后台下载（用户需求：不跳下载页，后台下完提醒）
    this.startDownload()
    return true
  }

  /** 双源竞速取 manifest：偏好非 auto 时只用对应源；auto 时 5s 先到先用，全失败才 null */
  private async fetchManifest(): Promise<UpdateManifest | null> {
    let urls: string[] = []
    if (this.pref === 'cn') {
      urls = [MANIFEST_CN_URL]
    } else if (this.pref === 'global') {
      urls = [MANIFEST_GLOBAL_URL]
    } else {
      urls = [MANIFEST_CN_URL, MANIFEST_GLOBAL_URL] // 竞速：都发，先到先用
    }
    const results: UpdateManifest[] = []
    const attempts = urls.map((u) => this.fetchManifestFrom(u)
      .then((m) => {
        if (m !== null) {
          results.push(m)
        }
        return m
      })
      .catch(() => {
        return null
      }))
    await Promise.all(attempts)
    if (results.length === 0) {
      console.info('[P69] manifest all sources failed')
      return null
    }
    return results[0]
  }

  private async fetchManifestFrom(url: string): Promise<UpdateManifest | null> {
    return new Promise<UpdateManifest | null>((resolve) => {
      const req = http.createHttp()
      const timer = setTimeout(() => {
        try {
          req.destroy()
        } catch (e) {
        }
        resolve(null)
      }, MANIFEST_TIMEOUT_MS)
      req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: MANIFEST_TIMEOUT_MS,
        readTimeout: MANIFEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      }).then((resp) => {
        clearTimeout(timer)
        try {
          req.destroy()
        } catch (e) {
        }
        if (resp.responseCode !== 200 || typeof resp.result !== 'string' || resp.result.length === 0) {
          console.info(`[P69] manifest ${url} http ${resp.responseCode}`)
          resolve(null)
          return
        }
        try {
          const raw = JSON.parse(resp.result) as Record<string, Object>
          const m = new UpdateManifest()
          m.versionCode = raw['versionCode'] as number
          m.versionName = `${raw['versionName'] ?? ''}`
          m.sha256 = `${raw['sha256'] ?? ''}`
          m.size = raw['size'] as number
          m.notes = `${raw['notes'] ?? ''}`
          m.minCompatibleApi = raw['minCompatibleApi'] as number
          const urls = raw['urls'] as Record<string, Object>
          m.globalUrls = UpdateServiceImpl.toStringArray(urls['global'])
          m.cnUrls = UpdateServiceImpl.toStringArray(urls['cn'])
          m.sourceUrl = url
          if (m.versionCode > 0 && m.sha256.length === 64 && (m.globalUrls.length > 0 || m.cnUrls.length > 0)) {
            resolve(m)
          } else {
            console.info('[P69] manifest invalid fields, ignore')
            resolve(null)
          }
        } catch (e) {
          console.info('[P69] manifest parse fail: ' + e)
          resolve(null)
        }
      }).catch((e: BusinessError) => {
        clearTimeout(timer)
        try {
          req.destroy()
        } catch (err) {
        }
        console.info(`[P69] manifest ${url} error: ${e.message}`)
        resolve(null)
      })
    })
  }

  private static toStringArray(v: Object | undefined): string[] {
    const out: string[] = []
    if (v !== undefined && Array.isArray(v)) {
      const arr = v as Object[]
      for (const it of arr) {
        const s = `${it}`
        if (it !== undefined && typeof it === 'string' && s.startsWith('https://')) {
          out.push(s)
        }
      }
    }
    return out
  }

  /** 当前 versionCode（bundleManager；1.1.0 = 1010000） */
  currentVersionCode(): number {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return info.versionCode
    } catch (e) {
      console.error('[P69] getBundleInfo fail: ' + e)
      return 0
    }
  }

  /** 按偏好排 URL 候选队列：cn 优先或 global 优先或竞速序（cn 先，global 兜底） */
  private candidateUrls(m: UpdateManifest): string[] {
    if (this.pref === 'cn') {
      return m.cnUrls.concat(m.globalUrls)
    }
    if (this.pref === 'global') {
      return m.globalUrls.concat(m.cnUrls)
    }
    return m.cnUrls.concat(m.globalUrls) // auto：国内优先（cn 首源+ghfast 兜底），再 global
  }

  /** 后台下载 + sha256 校验 + 失败换源重试（最多全候选一遍） */
  startDownload(): void {
    const m = this.state.manifest
    if (m === null || this.downloading) {
      return
    }
    this.downloading = true
    this.downloadWithFallback(this.candidateUrls(m), 0, m)
  }

  private downloadWithFallback(urls: string[], idx: number, m: UpdateManifest): void {
    if (idx >= urls.length) {
      this.downloading = false
      this.state.phase = UpdatePhase.FAILED
      this.state.error = 'all sources failed'
      this.emit()
      console.error('[P69] download all sources failed')
      return
    }
    const url = urls[idx]
    this.state.phase = UpdatePhase.DOWNLOADING
    this.state.attemptUrl = url
    this.state.receivedBytes = 0
    this.state.totalBytes = m.size
    this.state.progress = 0
    this.emit()
    console.info(`[P69] download try ${idx + 1}/${urls.length}: ${url}`)
    this.downloadFrom(url, m).then((ok) => {
      if (ok) {
        this.downloading = false
        this.state.phase = UpdatePhase.VERIFYING
        this.emit()
        const digest = UpdateServiceImpl.sha256File(this.state.readyPath)
        console.info(`[P69] sha256 ${digest === m.sha256 ? 'MATCH' : 'MISMATCH'} ${digest.slice(0, 12)} vs ${m.sha256.slice(0, 12)}`)
        if (digest === m.sha256) {
          this.state.phase = UpdatePhase.READY
          this.emit()
          this.cleanupOldPackages(m.versionName)
          return
        }
        // 校验失败：删残包，换下一源
        try {
          if (fs.accessSync(this.state.readyPath)) {
            fs.unlinkSync(this.state.readyPath)
          }
        } catch (e) {
        }
      }
      this.downloadWithFallback(urls, idx + 1, m)
    }).catch((e: BusinessError) => {
      console.error('[P69] download error: ' + e.message)
      this.downloadWithFallback(urls, idx + 1, m)
    })
  }

  private async downloadFrom(url: string, m: UpdateManifest): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const req = http.createHttp()
      this.httpReq = req
      const fname = `browseros-${m.versionName}.hap`
      const path = this.dir + '/' + fname
      let fd = -1
      try {
        fd = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC | fs.OpenMode.CREATE).fd
      } catch (e) {
        console.error('[P69] open file error: ' + e)
        try {
          req.destroy()
        } catch (err) {
        }
        resolve(false)
        return
      }
      let received = 0
      req.on('headersReceive', (header: Object) => {
        try {
          const h = header as Record<string, Object>
          const clV = h['content-length']
          const cl = clV !== undefined ? `${clV}` : ''
          if (cl.length > 0) {
            const n = Number(cl)
            if (!Number.isNaN(n) && n > 0) {
              this.state.totalBytes = n
            }
          }
        } catch (e) {
        }
      })
      req.on('dataReceive', (chunk: ArrayBuffer) => {
        try {
          fs.writeSync(fd, chunk)
          received += chunk.byteLength
          this.state.receivedBytes = received
          if (this.state.totalBytes > 0) {
            const p = Math.floor(received * 100 / this.state.totalBytes)
            if (p !== this.state.progress) {
              this.state.progress = p
              this.emit()
            }
          }
        } catch (e) {
          console.error('[P69] write chunk error: ' + e)
        }
      })
      req.requestInStream(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: DOWNLOAD_TIMEOUT_MS
      }).then((code: number) => {
        try {
          fs.closeSync(fd)
        } catch (e) {
        }
        try {
          req.destroy()
        } catch (e) {
        }
        this.httpReq = null
        const ok = code >= 200 && code < 400
        console.info(`[P69] download http ${code} bytes=${received} ok=${ok}`)
        if (ok) {
          this.state.readyPath = path
        } else {
          try {
            if (fs.accessSync(path)) {
              fs.unlinkSync(path)
            }
          } catch (e) {
          }
        }
        resolve(ok)
      }).catch((e: BusinessError) => {
        try {
          fs.closeSync(fd)
        } catch (err) {
        }
        try {
          req.destroy()
        } catch (err) {
        }
        this.httpReq = null
        console.error('[P69] download fail: ' + e.message)
        resolve(false)
      })
    })
  }

  /** cryptoFramework SHA-256 文件摘要（分块送入，hex 小写） */
  static sha256File(path: string): string {
    try {
      const md = cryptoFramework.createMd('SHA256')
      const f = fs.openSync(path, fs.OpenMode.READ_ONLY)
      try {
        const CHUNK = 1024 * 512
        const size = fs.statSync(path).size
        let off = 0
        while (off < size) {
          const len = Math.min(CHUNK, size - off)
          const buf = new ArrayBuffer(len)
          const n = fs.readSync(f.fd, buf, { offset: off, length: len })
          if (n <= 0) {
            break
          }
          md.updateSync({ data: new Uint8Array(buf.slice(0, n)) })
          off += n
        }
      } finally {
        try {
          fs.closeSync(f)
        } catch (e) {
        }
      }
      const out = md.digestSync()
      return Array.from(out.data).map((b: number) => b.toString(16).padStart(2, '0')).join('')
    } catch (e) {
      console.error('[P69] sha256 error: ' + e)
      return ''
    }
  }

  /**
   * 路径 A：投递 system_update 任务给任一在线 runner（P67 收件箱）。
   * runner(root) 将执行 bm install -r <hap> && aa start —— 应用被杀重启即新版。
   * 返回 false = 无在线 runner。
   */
  async applyViaRunner(): Promise<boolean> {
    if (this.state.phase !== UpdatePhase.READY || this.state.manifest === null) {
      return false
    }
    const agents = await DeviceAgentStore.listAgents()
    let runner: string = ''
    for (const a of agents) {
      if (DeviceAgentStore.isOnline(a)) {
        runner = a.name
        break
      }
    }
    if (runner.length === 0) {
      console.info('[P69] no online runner, path B')
      return false
    }
    this.state.phase = UpdatePhase.INSTALLING
    this.emit()
    const m = this.state.manifest
    const prompt = `SYSTEM_UPDATE||path=${this.state.readyPath}||sha256=${m.sha256}||version=${m.versionName}`
    const task = await DeviceAgentStore.createTask(runner, prompt, '', '', '', 'system_update')
    console.info(`[P69] system_update task ${task.taskId} -> runner ${runner}`)
    // 等待 runner 回写结果（最多 120s；runner 侧 bm install 通常 <30s）
    for (let i = 0; i < 60; i++) {
      await UpdateServiceImpl.sleep(2000)
      const t = await DeviceAgentStore.getTask(task.taskId)
      if (t === null) {
        continue
      }
      if (t.status === 'completed') {
        console.info(`[P69] system_update completed by runner: ${t.result.slice(0, 200)}`)
        return true
      }
      if (t.status === 'failed') {
        console.error(`[P69] system_update failed: ${t.result.slice(0, 200)}`)
        this.state.phase = UpdatePhase.READY
        this.state.error = t.result.slice(0, 120)
        this.emit()
        return true // 任务已回写（failed 也是完成态；UI 显示错误）
      }
    }
    console.warn('[P69] system_update result wait timeout')
    return true
  }

  static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms))
  }

  /** 成功安装后清理旧版本包（保留当前 readyPath 指向的最新包） */
  private cleanupOldPackages(keepVersion: string): void {
    try {
      const names = fs.listFileSync(this.dir)
      for (const n of names) {
        if (n.endsWith('.hap') && n !== `browseros-${keepVersion}.hap`) {
          try {
            fs.unlinkSync(this.dir + '/' + n)
            console.info('[P69] cleanup old package: ' + n)
          } catch (e) {
          }
        }
      }
    } catch (e) {
    }
  }

  private persistState(): void {
    const rec: Record<string, Object> = {}
    rec['lastAutoCheck'] = this.lastAutoCheck
    StorageManager.saveJSONSync(STATE_PATH, rec)
  }

  private emit(): void {
    EventBus.emit(EventBusEvents.UPDATE_STATE_CHANGE)
  }
}

export const UpdateService = new UpdateServiceImpl()
