import { BCPEngine } from './BCPEngine'
import { BCPResult } from '../common/Types'
import { Constants } from '../common/Constants'
import { PerformanceMonitor } from '../infra/PerformanceMonitor'

interface SnapshotNode {
  tag: string
  attrs: Record<string, string>
  children: SnapshotNode[]
  text?: string
}

class SnapshotGeneratorImpl {
  async generate(): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('snapshot_generate', 'Snapshot')
    // P12b: 直接产出紧凑 Markdown（页面侧已剔除噪音+可见性过滤+30000 截断），
    // 不再走 JSON 树 parse/compress（旧路径 data 为空时 compress(null.tag) 会崩）
    const mdResult = await BCPEngine.snapshotMarkdown()
    if (!mdResult.success) {
      timer()
      return mdResult
    }
    // P55: refs JSON string collected inline (empty on failure; snapshot still usable)
    const md = `${mdResult.data}`
    let refsJson = ''
    try {
      const refsResult = await BCPEngine.collectRefs()
      if (refsResult.success && refsResult.data) {
        refsJson = `${refsResult.data}`
      }
    } catch (e) {
      console.warn('[SnapshotGenerator] collectRefs failed: ' + e)
    }
    const combined: Record<string, Object> = { 'content': md, 'refs': refsJson }
    let combinedStr = md
    try {
      combinedStr = JSON.stringify(combined)
    } catch (e) {
    }
    timer()
    if (combinedStr.length > 0) {
      PerformanceMonitor.record('snapshot_original_size', combinedStr.length, 'Snapshot')
      PerformanceMonitor.record('snapshot_compressed_size', combinedStr.length, 'Snapshot')
      PerformanceMonitor.record('snapshot_compression_ratio', 1.0, 'Snapshot')
    }
    return { success: true, data: combinedStr, error: null }}

  private compress(node: SnapshotNode): SnapshotNode {
    const compressed: SnapshotNode = {
      tag: node.tag,
      attrs: this.compressAttrs(node.attrs),
      children: []
    }

    if (node.text) {
      compressed.text = this.truncateText(node.text, 100)
    }

    if (node.children && node.children.length > 0) {
      const filteredChildren = node.children
        .filter(child => this.isMeaningful(child))
        .map(child => this.compress(child))
      compressed.children = filteredChildren
    }

    return compressed
  }

  private compressAttrs(attrs: Record<string, string>): Record<string, string> {
    const compressed: Record<string, string> = {}
    for (const key of Object.keys(attrs)) {
      if (attrs[key]) {
        compressed[key] = this.truncateText(attrs[key], 200)
      }
    }
    return compressed
  }

  private truncateText(text: string, maxLength: number): string {
    if (text.length <= maxLength) {
      return text
    }
    return text.substring(0, maxLength) + '...'
  }

  private isMeaningful(node: SnapshotNode): boolean {
    if (node.tag === '#text' && node.text && node.text.trim().length > 0) {
      return true
    }
    if (node.children && node.children.length > 0) {
      return true
    }
    if (node.attrs && Object.keys(node.attrs).length > 0) {
      return true
    }
    return false
  }

  estimateCompression(originalHtml: string, snapshotJson: string): number {
    if (originalHtml.length === 0) {
      return 0
    }
    return snapshotJson.length / originalHtml.length
  }

  isWithinTarget(snapshotJson: string, originalHtml: string): boolean {
    const ratio = this.estimateCompression(originalHtml, snapshotJson)
    return ratio <= Constants.SNAPSHOT_COMPRESSION_RATIO
  }
}

export const SnapshotGenerator = new SnapshotGeneratorImpl()