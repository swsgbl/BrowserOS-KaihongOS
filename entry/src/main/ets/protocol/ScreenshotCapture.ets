import { BCPEngine } from './BCPEngine'
import { BCPResult } from '../common/Types'
import { Constants } from '../common/Constants'
import { PerformanceMonitor } from '../infra/PerformanceMonitor'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'

class ScreenshotCaptureImpl {
  async capture(quality: string = 'medium'): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('screenshot_capture', 'Screenshot')
    const result = await BCPEngine.screenshot(quality)
    timer()

    if (!result.success) {
      ErrorHandler.handle(new AppError(ErrorCodes.BCP_005, `Screenshot failed: ${result.error}`))
      return result
    }

    if (!result.data) {
      return { success: false, data: null, error: 'Screenshot data is empty' }
    }

    const dataPrefix = 'data:image/jpeg;base64,'
    if (!result.data.startsWith(dataPrefix) && !result.data.startsWith('data:image/png;base64,')) {
      return { success: true, data: `${dataPrefix}${result.data}`, error: null }
    }

    PerformanceMonitor.record('screenshot_data_size', result.data.length, 'Screenshot')

    return result
  }

  async captureLowQuality(): Promise<BCPResult> {
    return this.capture('low')
  }

  async captureMediumQuality(): Promise<BCPResult> {
    return this.capture('medium')
  }

  async captureHighQuality(): Promise<BCPResult> {
    return this.capture('high')
  }

  getQualityScale(quality: string): number {
    return Constants.SCREENSHOT_QUALITY_MAP[quality] || 0.6
  }

  validateBase64(data: string): boolean {
    if (!data) {
      return false
    }
    const base64Content = data.replace(/^data:image\/\w+;base64,/, '')
    if (base64Content.length === 0) {
      return false
    }
    try {
      return base64Content.length > 0
    } catch (e) {
      return false
    }
  }

  estimateSize(quality: string): number {
    const scale = this.getQualityScale(quality)
    const baseSize = 1920 * 1080 * 3
    return Math.round(baseSize * scale * 0.7)
  }
}

export const ScreenshotCapture = new ScreenshotCaptureImpl()