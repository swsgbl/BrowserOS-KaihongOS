// bug-1 修复: llmBaseUrl 拼接污染防御 (CRLF 安全版: 用不含换行的短锚点)
const fs = require('fs');
const ROOT = 'D:/BrowserOS - KaihongOS';

function replaceExact(file, from, to, expect) {
  const p = ROOT + '/' + file;
  let s = fs.readFileSync(p, 'utf8');
  const n = s.split(from).length - 1;
  if (n !== expect) throw new Error(`${file}: expected ${expect}x, found ${n}x of ${JSON.stringify(from.slice(0, 50))} - ABORT`);
  s = s.split(from).join(to);
  fs.writeFileSync(p, s);
  console.log(`OK ${file}: ${n}x replaced`);
}

const NL = fs.readFileSync(ROOT + '/entry/src/main/ets/model/AppConfig.ets', 'utf8').includes('\r\n') ? '\r\n' : '\n';

// --- 1. AppConfig: sanitize 静态方法 (插在 getDefault 之后) ---
replaceExact('entry/src/main/ets/model/AppConfig.ets',
`  static getDefault(): AppConfig {${NL}    return new AppConfig()${NL}  }`,
`  static getDefault(): AppConfig {${NL}    return new AppConfig()${NL}  }${NL}${NL}  /**${NL}   * bug-1 fix: 设备端 TextInput 受控回灌缺陷会把"旧值+新输入"无缝拼成${NL}   * "http://Ahttp://B" 形态的污染 URL。清洗策略: 按 http(s):// 边界切分,${NL}   * 取最后一段(用户最新输入意图), 保证落盘/生效的始终是单一 URL。${NL}   */${NL}  static sanitizeLlmBaseUrl(url: string): string {${NL}    let v = url.trim()${NL}    const parts = v.split(/(?=https?:\\/\\/)/)${NL}    if (parts.length > 1) {${NL}      v = parts[parts.length - 1].trim()${NL}    }${NL}    return v${NL}  }`, 1);

// --- 2. fromJSON 加载清洗 ---
replaceExact('entry/src/main/ets/model/AppConfig.ets',
`    config.llmBaseUrl = (json['llmBaseUrl'] as string) || ''`,
`    config.llmBaseUrl = AppConfig.sanitizeLlmBaseUrl((json['llmBaseUrl'] as string) || '')`, 1);

// --- 3. ConfigManager.set 清洗 ---
replaceExact('entry/src/main/ets/storage/ConfigManager.ets',
`      this.config.llmBaseUrl = config.llmBaseUrl.trim()`,
`      this.config.llmBaseUrl = AppConfig.sanitizeLlmBaseUrl(config.llmBaseUrl)`, 1);

console.log('BUG1 PATCH DONE');
