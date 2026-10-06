# -*- coding: utf-8 -*-
"""P2 patch part 1: AppConfig + ConfigManager LLM fields."""
import io, sys

def patch(path, replacements):
    with io.open(path, 'r', encoding='utf-8', newline=None) as f:
        t = f.read()
    for old, new in replacements:
        if old not in t:
            print('MISS: %r not found in %s' % (old[:60], path)); sys.exit(1)
        if t.count(old) != 1:
            print('DUP: %r appears %d times in %s' % (old[:60], t.count(old), path)); sys.exit(1)
        t = t.replace(old, new)
    with io.open(path, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(t)
    print('OK', path)

# ---- AppConfig.ets ----
APP = r'D:\BrowserOS - KaihongOS\entry\src\main\ets\model\AppConfig.ets'
patch(APP, [
    # interface JSON fields
    ("""  isOnboardingCompleted: boolean
  isNeoMode: boolean
  telemetryEnabled: boolean
}""",
     """  isOnboardingCompleted: boolean
  isNeoMode: boolean
  telemetryEnabled: boolean
  llmBaseUrl: string
  llmApiKey: string
  llmModel: string
}"""),
    # update interface
    ("""  isOnboardingCompleted?: boolean
  isNeoMode?: boolean
  telemetryEnabled?: boolean
}""",
     """  isOnboardingCompleted?: boolean
  isNeoMode?: boolean
  telemetryEnabled?: boolean
  llmBaseUrl?: string
  llmApiKey?: string
  llmModel?: string
}"""),
    # class defaults
    ("""  isOnboardingCompleted: boolean = false
  isNeoMode: boolean = false
  telemetryEnabled: boolean = false

  toJSON(): AppConfigJSON {""",
     """  isOnboardingCompleted: boolean = false
  isNeoMode: boolean = false
  telemetryEnabled: boolean = false
  llmBaseUrl: string = ''
  llmApiKey: string = ''
  llmModel: string = ''

  toJSON(): AppConfigJSON {"""),
    # toJSON body
    ("""      isOnboardingCompleted: this.isOnboardingCompleted,
      isNeoMode: this.isNeoMode,
      telemetryEnabled: this.telemetryEnabled
    }
    return result""",
     """      isOnboardingCompleted: this.isOnboardingCompleted,
      isNeoMode: this.isNeoMode,
      telemetryEnabled: this.telemetryEnabled,
      llmBaseUrl: this.llmBaseUrl,
      llmApiKey: this.llmApiKey,
      llmModel: this.llmModel
    }
    return result"""),
    # fromJSON
    ("""    config.isOnboardingCompleted = json['isOnboardingCompleted'] as boolean
    config.isNeoMode = json['isNeoMode'] as boolean
    config.telemetryEnabled = json['telemetryEnabled'] as boolean
    return config""",
     """    config.isOnboardingCompleted = json['isOnboardingCompleted'] as boolean
    config.isNeoMode = json['isNeoMode'] as boolean
    config.telemetryEnabled = json['telemetryEnabled'] as boolean
    config.llmBaseUrl = (json['llmBaseUrl'] as string) || ''
    config.llmApiKey = (json['llmApiKey'] as string) || ''
    config.llmModel = (json['llmModel'] as string) || ''
    return config"""),
    # validate
    ("""    if (this.recordingMaxSpaceMb < 100 || this.recordingMaxSpaceMb > 5000) {
      errors.push('recordingMaxSpaceMb must be between 100 and 5000')
    }
    return errors""",
     """    if (this.recordingMaxSpaceMb < 100 || this.recordingMaxSpaceMb > 5000) {
      errors.push('recordingMaxSpaceMb must be between 100 and 5000')
    }
    if (this.llmBaseUrl && !this.llmBaseUrl.startsWith('http://') && !this.llmBaseUrl.startsWith('https://')) {
      errors.push('llmBaseUrl must start with http:// or https://')
    }
    if (this.llmBaseUrl && this.llmBaseUrl.includes(' ')) {
      errors.push('llmBaseUrl must not contain spaces')
    }
    return errors"""),
])

# ---- ConfigManager.ets ----
CM = r'D:\BrowserOS - KaihongOS\entry\src\main\ets\storage\ConfigManager.ets'
patch(CM, [
    ("""    if (config.telemetryEnabled !== undefined) {
      this.config.telemetryEnabled = config.telemetryEnabled
    }
  }""",
     """    if (config.telemetryEnabled !== undefined) {
      this.config.telemetryEnabled = config.telemetryEnabled
    }
    if (config.llmBaseUrl !== undefined) {
      this.config.llmBaseUrl = config.llmBaseUrl.trim()
    }
    if (config.llmApiKey !== undefined) {
      this.config.llmApiKey = config.llmApiKey.trim()
    }
    if (config.llmModel !== undefined) {
      this.config.llmModel = config.llmModel.trim()
    }
  }"""),
    ("""  isNeoMode(): boolean {
    return this.config.isNeoMode
  }
}""",
     """  isNeoMode(): boolean {
    return this.config.isNeoMode
  }

  getLlmBaseUrl(): string {
    return this.config.llmBaseUrl
  }

  getLlmApiKey(): string {
    return this.config.llmApiKey
  }

  getLlmModel(): string {
    return this.config.llmModel
  }

  isLlmConfigured(): boolean {
    return this.config.llmBaseUrl.length > 0
  }
}"""),
])
print('ALL PATCHES OK')
