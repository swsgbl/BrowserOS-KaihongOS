/**
 * P16a: 下载管理器 —— @ohos.net.http requestInStream 流式下载到 files/downloads/
 * on('dataReceive') 增量落盘(不阻塞 UI)；Content-Length 取自 headersReceive；
 * DOWNLOAD_CHANGED 事件节流 500ms；启动从目录扫描恢复已完成列表。
 * 注: SDK14 OnDownloadStartEvent 无 suggestedFileName 字段，
 *     文件名从 contentDisposition(filename=) → url 末段 → 'download' 三级推导。
 */
import http from '@ohos.net.http'
import fs from '@ohos.file.fs'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'

export enum DownloadStatus {
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELED = 'canceled'
}

export class DownloadItem {
  id: string = ''
  url: string = ''
  fileName: string = ''
  filePath: string = ''
  mimeType: string = ''
  receivedBytes: number = 0
  totalBytes: number = 0
  status: DownloadStatus = DownloadStatus.RUNNING
  startedAt: number = 0
  finishedAt: number = 0
  error: string = ''
}

class DownloadManagerImpl {
  private downloads: DownloadItem[] = []
  private httpMap: Map<string, http.HttpRequest> = new Map()
  private canceledIds: Set<string> = new Set()
  private dir: string = ''
  private lastEmit: number = 0
  private inited: boolean = false

  init(context: common.UIAbilityContext): void {
    if (this.inited) {
      return
    }
    this.inited = true
    this.dir = context.filesDir + '/downloads'
    try {
      if (!fs.accessSync(this.dir)) {
        fs.mkdirSync(this.dir, true)
      }
    } catch (e) {
      console.error('[DownloadManager] mkdir error: ' + e)
    }
    this.scanDir()
    console.info('[DownloadManager] init dir=' + this.dir + ' restored=' + this.downloads.length)
  }

  /** P16a: static extractFileName 的实例包装(BrowserShell 调用点) */
  fileNameFrom(contentDisposition: string, url: string): string {
    return DownloadManagerImpl.extractFileName(contentDisposition, url)
  }

  getDir(): string {
    return this.dir
  }

  /** P19b: 清空下载记录并删除已落盘文件（进行中的先取消） */
  clearAllDownloads(): void {
    for (const item of this.downloads) {
      if (item.status === DownloadStatus.RUNNING) {
        this.cancel(item.id)
      }
    }
    // 删除已落盘文件
    try {
      const names = fs.listFileSync(this.dir)
      for (const name of names) {
        try {
          fs.unlinkSync(this.dir + '/' + name)
        } catch (e) {
          console.warn('[DownloadManager] clearAll unlink fail: ' + name)
        }
      }
    } catch (e) {
      console.warn('[DownloadManager] clearAll listDir fail')
    }
    this.downloads = []
    EventBus.emit(EventBusEvents.DOWNLOAD_CHANGED)
    console.info('[DownloadManager] clearAllDownloads done')
  }

  getDownloads(): DownloadItem[] {
    return this.downloads
  }

  hasActive(): boolean {
    for (const d of this.downloads) {
      if (d.status === DownloadStatus.RUNNING) {
        return true
      }
    }
    return false
  }

  /** SDK14 无 suggestedFileName：contentDisposition(filename= / filename*=UTF-8'') → url 末段 → 'download' */
  static extractFileName(contentDisposition: string, url: string): string {
    const cd = contentDisposition || ''
    let name = ''
    const starIdx = cd.indexOf("filename*=")
    if (starIdx >= 0) {
      const raw = cd.substring(starIdx + 10).split(';')[0].trim()
      const q = raw.indexOf("''")
      if (q >= 0) {
        name = decodeURIComponent(raw.substring(q + 2))
      }
    }
    if (name.length === 0) {
      const idx = cd.indexOf('filename=')
      if (idx >= 0) {
        name = cd.substring(idx + 9).split(';')[0].trim().replace(/^"|"$/g, '')
      }
    }
    if (name.length === 0 && url.length > 0) {
      try {
        let path = url.split('?')[0].split('#')[0]
        const slash = path.lastIndexOf('/')
        if (slash >= 0) {
          path = path.substring(slash + 1)
        }
        name = decodeURIComponent(path)
      } catch (e) {
        name = ''
      }
    }
    if (name.length === 0) {
      name = 'download_' + Date.now()
    }
    // 清洗路径分隔符与控制字符
    name = name.replace(/[\\/:*?"<>|]/g, '_').trim()
    if (name.length === 0 || name.length > 120) {
      name = name.length === 0 ? 'download_' + Date.now() : name.substring(name.length - 120)
    }
    return name
  }

  /** 同名冲突加 (n) 后缀 */
  private resolveFileName(raw: string): string {
    let base = raw
    let ext = ''
    const dot = raw.lastIndexOf('.')
    if (dot > 0 && dot < raw.length - 1) {
      base = raw.substring(0, dot)
      ext = raw.substring(dot)
    }
    let candidate = raw
    let n = 1
    const existsFn = (fn: string): boolean => {
      for (const d of this.downloads) {
        if (d.fileName === fn && d.status !== DownloadStatus.FAILED && d.status !== DownloadStatus.CANCELED) {
          return true
        }
      }
      try {
        return fs.accessSync(this.dir + '/' + fn)
      } catch (e) {
        return false
      }
    }
    while (existsFn(candidate)) {
      n++
      candidate = base + ' (' + n + ')' + ext
      if (n > 99) {
        candidate = base + '_' + Date.now() + ext
        break
      }
    }
    return candidate
  }

  start(url: string, fileName: string, mimeType: string): void {
    if (!this.inited) {
      console.error('[DownloadManager] not inited, ignore: ' + url)
      return
    }
    const item = new DownloadItem()
    item.id = 'dl_' + Date.now() + '_' + Math.floor(Math.random() * 100000)
    item.url = url
    item.fileName = this.resolveFileName(fileName.length > 0 ? fileName : 'download_' + Date.now())
    item.mimeType = mimeType
    item.filePath = this.dir + '/' + item.fileName
    item.startedAt = Date.now()
    item.status = DownloadStatus.RUNNING
    this.downloads.unshift(item)
    this.emit(true)
    console.info('[DownloadManager] start: ' + url + ' -> ' + item.fileName)

    const req = http.createHttp()
    this.httpMap.set(item.id, req)
    let fd = -1
    let opened = false
    try {
      fd = fs.openSync(item.filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC | fs.OpenMode.CREATE).fd
      opened = true
    } catch (e) {
      console.error('[DownloadManager] open file error: ' + e)
      this.finish(item.id, DownloadStatus.FAILED, 'open file error')
      req.destroy()
      this.httpMap.delete(item.id)
      return
    }

    req.on('headersReceive', (header: Object) => {
      try {
        const h = header as Record<string, string>
        const cl = h['content-length'] !== undefined ? h['content-length'] : h['Content-Length']
        if (cl !== undefined) {
          const n = Number(cl)
          if (!Number.isNaN(n) && n > 0) {
            item.totalBytes = n
            this.emit(false)
          }
        }
      } catch (e) {
        console.error('[DownloadManager] headers parse error: ' + e)
      }
    })
    req.on('dataReceive', (chunk: ArrayBuffer) => {
      try {
        fs.writeSync(fd, chunk)
        item.receivedBytes += chunk.byteLength
        this.emit(false)
      } catch (e) {
        console.error('[DownloadManager] write error: ' + e)
      }
    })
    req.on('dataEnd', () => {
      console.info('[DownloadManager] dataEnd: ' + item.fileName + ' bytes=' + item.receivedBytes)
    })
    req.requestInStream(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 15000,
      readTimeout: 120000
    }).then((code: number) => {
      if (code >= 400) {
        this.finish(item.id, DownloadStatus.FAILED, 'HTTP ' + code)
      } else {
        this.finish(item.id, DownloadStatus.COMPLETED, '')
      }
      if (opened) {
        try {
          fs.closeSync(fd)
        } catch (e) {
          console.error('[DownloadManager] close fd error: ' + e)
        }
      }
    }).catch((e: BusinessError) => {
      if (this.canceledIds.has(item.id)) {
        this.canceledIds.delete(item.id)
        this.finish(item.id, DownloadStatus.CANCELED, '')
      } else {
        const msg = e !== null && e.message !== undefined ? e.message : 'network error'
        this.finish(item.id, DownloadStatus.FAILED, msg)
      }
      if (opened) {
        try {
          fs.closeSync(fd)
        } catch (err) {
          console.error('[DownloadManager] close fd error: ' + err)
        }
      }
    })
  }

  cancel(id: string): void {
    const item = this.find(id)
    if (!item || item.status !== DownloadStatus.RUNNING) {
      return
    }
    this.canceledIds.add(id)
    const req = this.httpMap.get(id)
    if (req) {
      try {
        req.destroy()
      } catch (e) {
        console.error('[DownloadManager] destroy error: ' + e)
      }
    }
    console.info('[DownloadManager] cancel: ' + id)
  }

  retry(id: string): void {
    const item = this.find(id)
    if (!item || item.status !== DownloadStatus.FAILED) {
      return
    }
    // 旧条目移除，重新开始（保留原 url/名字推导）
    const url = item.url
    const name = item.fileName
    const mime = item.mimeType
    const idx = this.downloads.indexOf(item)
    if (idx >= 0) {
      this.downloads.splice(idx, 1)
    }
    this.start(url, name, mime)
  }

  private find(id: string): DownloadItem | null {
    for (const d of this.downloads) {
      if (d.id === id) {
        return d
      }
    }
    return null
  }

  private finish(id: string, status: DownloadStatus, error: string): void {
    const item = this.find(id)
    if (!item || item.status !== DownloadStatus.RUNNING) {
      return
    }
    item.status = status
    item.finishedAt = Date.now()
    item.error = error
    if (status === DownloadStatus.FAILED || status === DownloadStatus.CANCELED) {
      // 清理残缺文件
      try {
        if (fs.accessSync(item.filePath)) {
          fs.unlinkSync(item.filePath)
        }
      } catch (e) {
        console.error('[DownloadManager] cleanup error: ' + e)
      }
    }
    if (status === DownloadStatus.COMPLETED && item.totalBytes === 0) {
      item.totalBytes = item.receivedBytes
    }
    const req = this.httpMap.get(id)
    if (req) {
      try {
        req.destroy()
      } catch (e) {
        // ignore
      }
      this.httpMap.delete(id)
    }
    this.emit(true)
    console.info('[DownloadManager] finish: ' + item.fileName + ' status=' + status + ' bytes=' + item.receivedBytes + (error.length > 0 ? ' err=' + error : ''))
  }

  /** 启动扫描：已完成文件恢复进列表（无元数据，仅名字+大小） */
  private scanDir(): void {
    if (this.dir.length === 0) {
      return
    }
    try {
      const files = fs.listFileSync(this.dir)
      for (const f of files) {
        const full = this.dir + '/' + f
        try {
          const st = fs.statSync(full)
          if (!st.isFile()) {
            continue
          }
          const item = new DownloadItem()
          item.id = 'dlfile_' + f + '_' + st.mtime
          item.fileName = f
          item.filePath = full
          item.receivedBytes = st.size
          item.totalBytes = st.size
          item.status = DownloadStatus.COMPLETED
          item.startedAt = st.mtime * 1000
          item.finishedAt = st.mtime * 1000
          this.downloads.push(item)
        } catch (e) {
          console.error('[DownloadManager] stat error: ' + full)
        }
      }
      // 时间降序
      this.downloads.sort((a: DownloadItem, b: DownloadItem): number => b.finishedAt - a.finishedAt)
    } catch (e) {
      console.error('[DownloadManager] scanDir error: ' + e)
    }
  }

  /** 节流 500ms 广播（完成/失败/新增强制立即） */
  private emit(force: boolean): void {
    const now = Date.now()
    if (!force && now - this.lastEmit < 500) {
      return
    }
    this.lastEmit = now
    EventBus.emit(EventBusEvents.DOWNLOAD_CHANGED)
  }
}

export const DownloadManager = new DownloadManagerImpl()
