/* P47 Phase3: Reader mode (E) + generic form fill (F) */
const fs = require('fs');
const ETS = 'D:/BrowserOS - KaihongOS/entry/src/main/ets';

function loadFile(p) {
  const raw = fs.readFileSync(p, 'utf8');
  const eol = (raw.match(/\r\n/g) || []).length >= (raw.match(/\n/g) || []).length / 2 ? '\r\n' : '\n';
  return { text: raw.replace(/\r\n/g, '\n'), eol };
}
function saveFile(p, text, eol) {
  fs.writeFileSync(p, eol === '\r\n' ? text.replace(/\n/g, '\r\n') : text, 'utf8');
}
function patch(src, oldStr, newStr, tag) {
  const i = src.indexOf(oldStr);
  if (i < 0) throw new Error('PATCH MISS: ' + tag);
  if (src.indexOf(oldStr, i + 1) >= 0) throw new Error('PATCH DUP: ' + tag);
  return src.slice(0, i) + newStr + src.slice(i + oldStr.length);
}

/* ---------- BrowserShell: reader mode + form fill ---------- */
const shF = loadFile(ETS + '/pages/BrowserShell.ets');
let sh = shF.text;

// states
sh = patch(sh, "  @State p47ZoomToast: string = ''",
  "  @State p47ZoomToast: string = ''\n" +
  "  // P47-E: \u9605\u8bfb\u6a21\u5f0f\n" +
  "  @State p47ReaderOpen: boolean = false\n" +
  "  @State p47ReaderTitle: string = ''\n" +
  "  @State p47ReaderHtml: string = ''",
  'states3');

// menu actions
sh = patch(sh, "      case 'zoom_in':",
  "      case 'reader':\n" +
  "        this.p47OpenReader()\n" +
  "        break\n" +
  "      case 'fill_form':\n" +
  "        this.p47FillForm()\n" +
  "        break\n" +
  "      case 'zoom_in':",
  'menu3');

// methods before p47DomainOf
sh = patch(sh, "  /** P47-B: \u57df\u540d\u63d0\u53d6 */",
  "  /** P47-E: \u9605\u8bfb\u6a21\u5f0f \u2014\u2014 \u62bd\u53d6\u9875\u9762\u6b63\u6587\uff08\u6807\u9898+h1~p\uff09\u6e32\u67d3\u5e72\u51c0\u6392\u7248 */\n" +
  "  private p47OpenReader(): void {\n" +
  "    const ctrl = this.getActiveController()\n" +
  "    if (!ctrl) {\n" +
  "      return\n" +
  "    }\n" +
  "    const js = \"(function(){function pick(sel){var els=document.querySelectorAll(sel);var best=null;var bl=0;for(var i=0;i<els.length;i++){var t=(els[i].textContent||'').trim();if(t.length>bl){best=t;bl=t.length}}return best}var h1=pick('h1');var ps=[];var pel=document.querySelectorAll('article p,main p,#content p,.content p,p');var seen={};for(var i=0;i<pel.length&&ps.length<200;i++){var t=(pel[i].textContent||'').trim();if(t.length>40&&!seen[t]){seen[t]=1;ps.push(t)}}return JSON.stringify({t:document.title,h:h1||document.title,p:ps})})()\"\n" +
  "    ctrl.runJavaScript(js).then((r: string) => {\n" +
  "      let s = r.replace(/^\"|\"$/g, '').replace(/\\\\\"/g, '\"')\n" +
  "      try {\n" +
  "        const obj = JSON.parse(s) as Record<string, Object>\n" +
  "        const ps = obj['p'] as string[] | undefined\n" +
  "        if (!ps || ps.length === 0) {\n" +
  "          this.p47FlashToast('\u672a\u627e\u5230\u53ef\u8bfb\u6b63\u6587')\n" +
  "          return\n" +
  "        }\n" +
  "        this.p47ReaderTitle = this.asStr(obj['h'])\n" +
  "        let html = ''\n" +
  "        for (const p of ps) {\n" +
  "          html += '<p>' + p + '</p>'\n" +
  "        }\n" +
  "        this.p47ReaderHtml = html\n" +
  "        this.p47ReaderOpen = true\n" +
  "        console.info('[P47] reader: ' + ps.length + ' paragraphs')\n" +
  "      } catch (e) {\n" +
  "        this.p47FlashToast('\u9605\u8bfb\u6a21\u5f0f\u63d0\u53d6\u5931\u8d25')\n" +
  "      }\n" +
  "    }).catch(() => {\n" +
  "      this.p47FlashToast('\u5f53\u524d\u9875\u9762\u4e0d\u652f\u6301\u9605\u8bfb')\n" +
  "    })\n" +
  "  }\n" +
  "\n" +
  "  private asStr(v: Object | undefined): string {\n" +
  "    return typeof v === 'string' ? v : ''\n" +
  "  }\n" +
  "\n" +
  "  /** P47-F: \u901a\u7528\u8868\u5355\u586b\u5145 \u2014\u2014 \u6309 name/id/placeholder/autocomplete/\u7c7b\u578b\u542f\u53d1\uff0c\u5df2\u767b\u5f55\u7f51\u7ad9\u7528\u5bc6\u7801\u5e93\uff0c\u5176\u4ed6\u7528\u793a\u4f8b\u6570\u636e */\n" +
  "  private p47FillForm(): void {\n" +
  "    const ctrl = this.getActiveController()\n" +
  "    if (!ctrl) {\n" +
  "      return\n" +
  "    }\n" +
  "    const domain = this.p47DomainOf(this.currentUrl)\n" +
  "    const cred = domain.length > 0 ? CredentialStore.getByDomain(domain) : []\n" +
  "    const u = cred.length > 0 ? JSON.stringify(cred[0].username) : '\"user@example.com\"'\n" +
  "    const p = cred.length > 0 ? JSON.stringify(cred[0].password) : '\"P47SamplePass!\"'\n" +
  "    const js = \"(function(){function sv(el,v){var pr=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');if(pr&&pr.set){pr.set.call(el,v)}else{el.value=v}el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))}var n=0;var ins=document.querySelectorAll('input');for(var i=0;i<ins.length;i++){var el=ins[i];var t=el.type||'text';if(t==='hidden'||t==='file'||t==='checkbox'||t==='radio'||t==='submit'||t==='button')continue;var key=((el.name||'')+' '+(el.id||'')+' '+(el.placeholder||'')+' '+(el.autocomplete||'')+' '+t).toLowerCase();var v=null;if(t==='email'||key.indexOf('email')>=0||key.indexOf('mail')>=0){v=\" + u + \"}else if(t==='password'||key.indexOf('pass')>=0||key.indexOf('pwd')>=0){v=\" + p + \"}else if(t==='tel'||key.indexOf('phone')>=0||key.indexOf('mobile')>=0){v='13800138000'}else if(key.indexOf('name')>=0&&key.indexOf('user')<0&&key.indexOf('file')<0){v='\u5f20\u4e09'}else if(key.indexOf('user')>=0||key.indexOf('account')>=0||key.indexOf('login')>=0){v=\" + u + \"}if(v!==null){sv(el,String(v));n++}}return String(n)})()\"\n" +
  "    ctrl.runJavaScript(js).then((r: string) => {\n" +
  "      this.p47FlashToast('\u5df2\u586b\u5145 ' + r.replace(/\\\"/g, '') + ' \u4e2a\u5b57\u6bb5')\n" +
  "      console.info('[P47] form filled: ' + r)\n" +
  "    }).catch(() => {\n" +
  "      this.p47FlashToast('\u8868\u5355\u586b\u5145\u5931\u8d25')\n" +
  "    })\n" +
  "  }\n" +
  "\n" +
  "  /** P47-B: \u57df\u540d\u63d0\u53d6 */",
  'methods3');

// reader overlay UI before P33-D changelog
sh = patch(sh, "      // P47-B: \u5bc6\u7801\u586b\u5145\u63d0\u793a\u6761\uff08\u5e95\u90e8\u60ac\u6d6e\uff09",
  "      // P47-E: \u9605\u8bfb\u6a21\u5f0f\u5f39\u5c42\n" +
  "      if (this.p47ReaderOpen) {\n" +
  "        Column() {\n" +
  "          Row() {\n" +
  "            Button({ type: ButtonType.Normal }) {\n" +
  "              Image($rawfile('ic_back.svg'))\n" +
  "                .width(20).height(20)\n" +
  "                .fillColor(this.pal().text)\n" +
  "                .draggable(false)\n" +
  "            }\n" +
  "            .width(40).height(40)\n" +
  "            .backgroundColor(Color.Transparent)\n" +
  "            .onClick(() => { this.p47ReaderOpen = false })\n" +
  "            Text(this.p47ReaderTitle)\n" +
  "              .fontSize(16)\n" +
  "              .fontWeight(FontWeight.Bold)\n" +
  "              .fontColor(this.pal().text)\n" +
  "              .layoutWeight(1)\n" +
  "              .maxLines(1)\n" +
  "              .textOverflow({ overflow: TextOverflow.Ellipsis })\n" +
  "            Text('\u9605\u8bfb\u6a21\u5f0f')\n" +
  "              .fontSize(11)\n" +
  "              .fontColor(this.pal().text2)\n" +
  "              .margin({ right: 12 })\n" +
  "          }\n" +
  "          .width('100%')\n" +
  "          .height(52)\n" +
  "          .padding({ left: 8, right: 12 })\n" +
  "          Scroll() {\n" +
  "            Text(this.p47ReaderHtml.replace(/<\\/?p>/g, '\\n'))\n" +
  "              .fontSize(16)\n" +
  "              .lineHeight(28)\n" +
  "              .fontColor(this.pal().text)\n" +
  "              .padding(20)\n" +
  "          }\n" +
  "          .layoutWeight(1)\n" +
  "          .align(Alignment.Top)\n" +
  "        }\n" +
  "        .width('100%')\n" +
  "        .height('100%')\n" +
  "        .backgroundColor(this.pal().surface)\n" +
  "      }\n" +
  "      // P47-B: \u5bc6\u7801\u586b\u5145\u63d0\u793a\u6761\uff08\u5e95\u90e8\u60ac\u6d6e\uff09",
  'reader-ui');

saveFile(ETS + '/pages/BrowserShell.ets', sh, shF.eol);
console.log('BrowserShell phase3 OK');

/* ---------- ChromeWidgets menu ---------- */
const cwF = loadFile(ETS + '/components/ChromeWidgets.ets');
let cw = cwF.text;
cw = patch(cw, "    { icon: $rawfile('ic_bug.svg'), label: '\u5f00\u53d1\u8005\u5de5\u5177', action: 'devtools' },",
  "    { icon: $rawfile('ic_reader.svg'), label: '\u9605\u8bfb\u6a21\u5f0f', action: 'reader' },\n" +
  "    { icon: $rawfile('ic_edit.svg'), label: '\u586b\u5145\u8868\u5355', action: 'fill_form' },\n" +
  "    { icon: $rawfile('ic_bug.svg'), label: '\u5f00\u53d1\u8005\u5de5\u5177', action: 'devtools' },", 'menu3');
saveFile(ETS + '/components/ChromeWidgets.ets', cw, cwF.eol);
console.log('ChromeWidgets phase3 OK');
console.log('PHASE3 PATCHES OK');
