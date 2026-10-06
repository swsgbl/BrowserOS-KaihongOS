const fs = require('fs');
const path = require('path');
const ROOT = 'D:\\BrowserOS - KaihongOS\\entry\\src\\main\\ets';

function patch(file, replacements) {
  const p = path.join(ROOT, file);
  let c = fs.readFileSync(p, 'utf8');
  for (const [oldStr, newStr] of replacements) {
    if (!c.includes(oldStr)) {
      console.log('MISS: ' + file + ' :: ' + oldStr.slice(0, 60).replace(/\r?\n/g, '\\n'));
      process.exitCode = 1;
      continue;
    }
    c = c.split(oldStr).join(newStr);
  }
  fs.writeFileSync(p, c);
  console.log('OK: ' + file);
}

// 1. AgentStatus.updateHeartbeat: compute duration BEFORE updating lastHeartbeat
patch('model/AgentStatus.ets', [
  ["    this.lastHeartbeat = Date.now()\r\n    this.runningDuration = Date.now() - this.lastHeartbeat",
   "    this.runningDuration = Date.now() - this.lastHeartbeat\r\n    this.lastHeartbeat = Date.now()"]
]);

// 2. SessionRecord: toJSON include operationLogs/screenshots; fromJSON restore them
patch('model/SessionRecord.ets', [
  ["  filePath: string\r\n  fileSize: number\r\n  isCorrupted: boolean\r\n}",
   "  filePath: string\r\n  fileSize: number\r\n  operationLogs: OperationLogJSON[]\r\n  screenshots: ScreenshotEntryJSON[]\r\n  isCorrupted: boolean\r\n}"],
  ["      filePath: this.filePath,\r\n      fileSize: this.fileSize,\r\n      isCorrupted: this.isCorrupted",
   "      filePath: this.filePath,\r\n      fileSize: this.fileSize,\r\n      operationLogs: this.operationLogs.map((log: OperationLog): OperationLogJSON => log.toJSON()),\r\n      screenshots: this.screenshots.map((shot: ScreenshotEntry): ScreenshotEntryJSON => shot.toJSON()),\r\n      isCorrupted: this.isCorrupted"],
  ["    record.isCorrupted = json['isCorrupted'] as boolean\r\n    return record",
   "    record.isCorrupted = json['isCorrupted'] as boolean\r\n    const logs = json['operationLogs'] as Object[] | undefined\r\n    if (logs) {\r\n      for (const item of logs) {\r\n        record.operationLogs.push(OperationLog.fromJSON(item as Record<string, Object>))\r\n      }\r\n    }\r\n    const shots = json['screenshots'] as Object[] | undefined\r\n    if (shots) {\r\n      for (const item of shots) {\r\n        record.screenshots.push(ScreenshotEntry.fromJSON(item as Record<string, Object>))\r\n      }\r\n    }\r\n    return record"]
]);

// 3. StorageManager.load(): decode via TextDecoder (utf-8) instead of String.fromCharCode loop
patch('storage/StorageManager.ets', [
  ["import { fileIo as fs } from '@kit.CoreFileKit'",
   "import { fileIo as fs } from '@kit.CoreFileKit'\r\nimport { util } from '@kit.ArkTS'"],
  ["      const buffer = new ArrayBuffer(stat.size)\r\n      fs.readSync(file.fd, buffer)\r\n      fs.closeSync(file)\r\n      const view = new Uint8Array(buffer)\r\n      let result = ''\r\n      for (let i = 0; i < view.length; i++) {\r\n        result += String.fromCharCode(view[i])\r\n      }\r\n      return result",
   "      const buffer = new ArrayBuffer(stat.size)\r\n      fs.readSync(file.fd, buffer)\r\n      fs.closeSync(file)\r\n      const decoder = util.TextDecoder.create('utf-8')\r\n      return decoder.decodeWithStream(new Uint8Array(buffer))"]
]);
console.log('done');
