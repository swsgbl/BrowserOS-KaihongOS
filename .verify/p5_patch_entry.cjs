const fs = require('fs');

// ---- 3a: EntryAbility conditional page load ----
const p1 = 'entry/src/main/ets/entryability/EntryAbility.ets';
let a = fs.readFileSync(p1, 'utf8').replace(/\r\n/g, '\n');
const OLD1 = `  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('BrowserOS KaihongOS EntryAbility onWindowStageCreate')
    windowStage.loadContent('pages/BrowserShell', (err: BusinessError) => {`;
const NEW1 = `  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('BrowserOS KaihongOS EntryAbility onWindowStageCreate')
    // P5: 首启动 Onboarding —— 未完成配置则进入引导页
    const entryPage = ConfigManager.isOnboardingCompleted() ? 'pages/BrowserShell' : 'pages/OnboardingPage'
    console.info('EntryAbility entry page: ' + entryPage + ' (onboardingCompleted=' + ConfigManager.isOnboardingCompleted() + ')')
    windowStage.loadContent(entryPage, (err: BusinessError) => {`;
if (!a.includes(OLD1)) { throw new Error('EntryAbility anchor not found'); }
a = a.replace(OLD1, NEW1);
fs.writeFileSync(p1, a.replace(/\n/g, '\r\n'), 'utf8');
console.log('EntryAbility patched');

// ---- 3b: OnboardingPage completion -> BrowserShell ----
const p2 = 'entry/src/main/ets/pages/OnboardingPage.ets';
let b = fs.readFileSync(p2, 'utf8').replace(/\r\n/g, '\n');
const OLD2 = `        .onClick(() => {
          const updateData: AppConfigUpdate = { isOnboardingCompleted: true }
          ConfigManager.update(updateData)
        })`;
const NEW2 = `        .onClick(() => {
          const updateData: AppConfigUpdate = { isOnboardingCompleted: true }
          ConfigManager.update(updateData)
          console.info('OnboardingPage completed, entering BrowserShell')
          router.replaceUrl({ url: 'pages/BrowserShell' })
        })`;
if (!b.includes(OLD2)) { throw new Error('Onboarding anchor not found'); }
b = b.replace(OLD2, NEW2);
if (!b.includes("import { AppConfigUpdate } from '../model/AppConfig'")) { throw new Error('import anchor missing'); }
b = b.replace("import { AppConfigUpdate } from '../model/AppConfig'",
  "import { AppConfigUpdate } from '../model/AppConfig'\nimport { router } from '@kit.ArkUI'");
fs.writeFileSync(p2, b.replace(/\n/g, '\r\n'), 'utf8');
console.log('OnboardingPage patched');
