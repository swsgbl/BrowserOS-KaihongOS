const fs = require('fs');
function patch(file, patches) {
  let text = fs.readFileSync(file, 'utf8');
  for (const p of patches) {
    const oldS = p.old.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
    const newS = p.new.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
    const count = text.split(oldS).length - 1;
    if (count !== 1) { console.error('FAIL ' + file + ' hits=' + count + ' head=' + JSON.stringify(p.old.slice(0, 60))); process.exit(1); }
    text = text.replace(oldS, newS);
  }
  fs.writeFileSync(file, text, 'utf8');
  console.log('OK ' + file);
}

const F = 'D:\\BrowserOS - KaihongOS\\entry\\src\\main\\ets\\service\\HttpMcpTransport.ets';

patch(F, [
  {
    // silence the second-iteration noise log for empty buffer
    old: `    let guard = 0
    while (guard++ < 32) {
      let headerEnd = this.findHeaderEnd(buf)`,
    new: `    let guard = 0
    while (guard++ < 32) {
      if (buf.length === 0) {
        break
      }
      let headerEnd = this.findHeaderEnd(buf)`
  },
  {
    // REAL fix: skip decodeUtf8 on empty body (decodeWithStream(empty) returns undefined
    // on this netstack -> bodyText.length throws inside async dispatch -> swallowed rejection -> client hangs)
    old: `      const bodyText = loose ? '' : this.decodeUtf8(buf.subarray(headerEnd + 4, total))`,
    new: `      // P4 fix2 (real root cause): decodeWithStream on an EMPTY Uint8Array returns undefined
      // on this netstack; bodyText.length then throws inside async dispatch and the rejection
      // is swallowed -> client hangs forever. GET/empty-body requests must skip decode entirely.
      const bodyText = (loose || contentLength === 0) ? '' : this.decodeUtf8(buf.subarray(headerEnd + 4, total))`
  },
  {
    // surface future dispatch rejections instead of swallowing
    old: `      this.dispatch(conn, headerText, bodyText)
    }
    conn.buffer = buf`,
    new: `      this.dispatch(conn, headerText, bodyText).catch((e: BusinessError) => {
        console.error(\`[\${TAG}] dispatch async error: \${e.code}/\${e.message}\`)
      })
    }
    conn.buffer = buf`
  }
]);
console.log('PATCH2 DONE');
