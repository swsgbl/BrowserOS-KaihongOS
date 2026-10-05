import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('BrowserOS KaihongOS EntryAbility onCreate')
  }

  onDestroy(): void {
    console.info('BrowserOS KaihongOS EntryAbility onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('BrowserOS KaihongOS EntryAbility onWindowStageCreate')
    windowStage.loadContent('pages/BrowserShell', (err: BusinessError) => {
      if (err.code) {
        console.error(`Failed to load UI content: ${err.message}`)
        return
      }
      console.info('UI content loaded successfully')
    })
  }

  onWindowStageDestroy(): void {
    console.info('BrowserOS KaihongOS EntryAbility onWindowStageDestroy')
  }

  onForeground(): void {
    console.info('BrowserOS KaihongOS EntryAbility onForeground')
  }

  onBackground(): void {
    console.info('BrowserOS KaihongOS EntryAbility onBackground')
  }
}