interface PerformanceMetric {
  name: string
  value: number
  timestamp: number
  module: string
}

interface MetricData {
  avg: number
  min: number
  max: number
  count: number
}

class PerformanceMonitorImpl {
  private metrics: PerformanceMetric[] = []
  private maxMetrics: number = 1000
  private enabled: boolean = true

  record(name: string, value: number, module: string): void {
    if (!this.enabled) {
      return
    }
    this.metrics.push({
      name,
      value,
      timestamp: Date.now(),
      module
    })
    if (this.metrics.length > this.maxMetrics) {
      this.metrics.shift()
    }
  }

  startTimer(name: string, module: string): () => void {
    const startTime = Date.now()
    return () => {
      const duration = Date.now() - startTime
      this.record(name, duration, module)
    }
  }

  getMetrics(name?: string, module?: string): PerformanceMetric[] {
    return this.metrics.filter(m => {
      if (name && m.name !== name) {
        return false
      }
      if (module && m.module !== module) {
        return false
      }
      return true
    })
  }

  getAverage(name: string, module?: string): number {
    const filtered = this.getMetrics(name, module)
    if (filtered.length === 0) {
      return 0
    }
    const sum = filtered.reduce((acc, m) => acc + m.value, 0)
    return sum / filtered.length
  }

  clear(): void {
    this.metrics = []
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled
  }

  isEnabled(): boolean {
    return this.enabled
  }

  getSummary(): Record<string, Object> {
    const summary: Record<string, Object> = {}
    const moduleMap: Map<string, PerformanceMetric[]> = new Map()

    for (const metric of this.metrics) {
      if (!moduleMap.has(metric.module)) {
        moduleMap.set(metric.module, [])
      }
      moduleMap.get(metric.module)!.push(metric)
    }

    moduleMap.forEach((metrics: PerformanceMetric[], module: string) => {
      const names: Map<string, number[]> = new Map()
      for (const m of metrics) {
        if (!names.has(m.name)) {
          names.set(m.name, [])
        }
        names.get(m.name)!.push(m.value)
      }

      const moduleSummary: Record<string, Object> = {}
      names.forEach((values: number[], name: string) => {
        const avg = values.reduce((a, b) => a + b, 0) / values.length
        const metricData: MetricData = {
          avg: Math.round(avg),
          min: Math.min(...values),
          max: Math.max(...values),
          count: values.length
        }
        moduleSummary[name] = metricData
      })
      summary[module] = moduleSummary
    })

    return summary
  }
}

export const PerformanceMonitor = new PerformanceMonitorImpl()