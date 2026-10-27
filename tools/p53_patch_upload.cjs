// P53: BrowserShell Web 组件挂 onShowFileSelector（上传闭环）+ pdf 按需注入辅助
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/BrowserShell.ets'
let t = fs.readFileSync(P, 'utf8')

// 锚: .onDownloadStart( 链之前插入 onShowFileSelector（挂在 onControllerAttached 之后）
const anchor = "          .onDownloadStart((e) => {"
if (!t.includes(anchor)) { console.error('MISS onDownloadStart anchor'); process.exit(1) }
const block =
  "          // P53: 文件选择注入（upload 闭环）—— 页面 <input type=file> 触发\r\n" +
  "          .onShowFileSelector((event: OnShowFileSelectorEvent) => {\r\n" +
  "            if (event && event.fileSelector && event.result) {\r\n" +
  "              const fsParam = event.fileSelector\r\n" +
  "              console.info('[P53] onShowFileSelector title=' + fsParam.getTitle() +\r\n" +
  "                ' mode=' + fsParam.getMode() + ' accept=' + fsParam.getAcceptType().join(','))\r\n" +
  "              try {\r\n" +
  "                const hostCtx = this.getUIContext().getHostContext()\r\n" +
  "                const docPicker = hostCtx !== undefined ? new picker.DocumentViewPicker(hostCtx) : new picker.DocumentViewPicker()\r\n" +
  "                const opts = new picker.DocumentSelectOptions()\r\n" +
  "                opts.maxSelectNumber = 1\r\n" +
  "                docPicker.select(opts).then((uris: Array<string>) => {\r\n" +
  "                  if (uris.length > 0) {\r\n" +
  "                    console.info('[P53] file selected for upload: ' + uris[0])\r\n" +
  "                    event.result.handleFileList(uris)\r\n" +
  "                  } else {\r\n" +
  "                    event.result.handleFileList([])\r\n" +
  "                  }\r\n" +
  "                }).catch((e: Object) => {\r\n" +
  "                  console.info('[P53] upload picker dismissed: ' + e)\r\n" +
  "                  event.result.handleFileList([])\r\n" +
  "                })\r\n" +
  "              } catch (e) {\r\n" +
  "                console.error('[P53] onShowFileSelector error: ' + e)\r\n" +
  "                event.result.handleFileList([])\r\n" +
  "              }\r\n" +
  "            }\r\n" +
  "            return true\r\n" +
  "          })\r\n" +
  "          .onDownloadStart((e) => {"
t = t.replace(anchor, block)

// import picker 检查
if (!/import \{ picker \} from '@kit.CoreFileKit'/.test(t)) {
  const ia = t.indexOf("import { webview } from '@kit.ArkWeb'")
  if (ia < 0) { console.error('MISS webview import line'); process.exit(1) }
  const lineEnd = t.indexOf('\n', ia)
  t = t.slice(0, lineEnd + 1) + "import { picker } from '@kit.CoreFileKit'\r\n" + t.slice(lineEnd + 1)
}

fs.writeFileSync(P, t, 'utf8')
const v = fs.readFileSync(P, 'utf8')
if (!v.includes('onShowFileSelector') || !v.includes("import { picker } from '@kit.CoreFileKit'")) { console.error('VERIFY FAIL'); process.exit(1) }
console.log('OK: onShowFileSelector wired + picker imported')
