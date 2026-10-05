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
    const result = await BCPEngine.snapshot()
    timer()

    if (!result.success || !result.data) {
      return result
    }

    try {
      const snapshot = JSON.parse(result.data) as SnapshotNode
      const compressed = this.compress(snapshot)
      const compressedJson = JSON.stringify(compressed)
      const originalSize = result.data.length
      const compressedSize = compressedJson.length
      const ratio = compressedSize / originalSize

      PerformanceMonitor.record('snapshot_compression_ratio', ratio, 'Snapshot')
      PerformanceMonitor.record('snapshot_original_size', originalSize, 'Snapshot')
      PerformanceMonitor.record('snapshot_compressed_size', compressedSize, 'Snapshot')

      return {
        success: true,
        data: compressedJson,
        error: null
      }
    } catch (e) {
      return {
        success: false,
        data: null,
        error: `Snapshot parse failed: ${e}`
      }
    }
  }

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