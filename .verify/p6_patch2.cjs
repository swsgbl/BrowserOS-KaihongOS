const fs = require('fs');
const f = 'entry/src/main/ets/service/AgentEngine.ets';
let c = fs.readFileSync(f, 'utf8');
const N = '\r\n';

const old1 = "    if (!bound) {" + N + "      console.warn('[AgentEngine] WebView not registered for tab ' + config.tabId + ' after 10s, agent tools will fail')" + N + "    }";
const new1 = "    if (!bound) {" + N + "      console.warn('[AgentEngine] WebView not registered for tab ' + config.tabId + ' after 10s, agent tools will fail')" + N + "    } else if (config.targetUrl && config.targetUrl.length > 0) {" + N + "      // P6: agent tab 创建即自动导航到目标页（Web 层常驻架构，前台后台均生效），" + N + "      // 消灭「依赖人工点击 tab 触发渲染」的时序缺口" + N + "      try {" + N + "        BCPEngine.navigate(config.targetUrl)" + N + "        console.info('[AgentEngine] auto-navigate agent tab to target: ' + config.targetUrl)" + N + "      } catch (e) {" + N + "        console.warn('[AgentEngine] auto-navigate failed: ' + e)" + N + "      }" + N + "    }";
if (!c.includes(old1)) { console.error('E1 NOT FOUND'); process.exit(1); }
c = c.replace(old1, new1);

const old2 = "        const sensitive = SensitiveOperationDetector.detectNavigation(agentId, url)" + N + "        if (sensitive) {" + N + "          return this.bcpFail(`sensitive navigation blocked: ${sensitive}`)" + N + "        }";
const new2 = "        const sensitive = SensitiveOperationDetector.detectNavigation(agentId, url)" + N + "        if (sensitive) {" + N + "          // P6: 敏感导航走用户确认链（ConfirmDialog → Promise resolve），不再静默拦截" + N + "          console.info('[AgentEngine] sensitive navigate -> requestConfirmation: ' + sensitive + ' url=' + url)" + N + "          const confirmed = await SensitiveOperationDetector.requestConfirmation(agentId, sensitive, url, '')" + N + "          console.info('[AgentEngine] requestConfirmation resolved: ' + confirmed)" + N + "          if (!confirmed) {" + N + "            return this.bcpFail(`sensitive navigation rejected by user: ${sensitive}`)" + N + "          }" + N + "        }";
if (!c.includes(old2)) { console.error('E2 NOT FOUND'); process.exit(1); }
c = c.replace(old2, new2);

const old3 = "        const sensitive = SensitiveOperationDetector.detectClick(agentId, selector, '')" + N + "        if (sensitive) {" + N + "          return this.bcpFail(`sensitive click blocked: ${sensitive}`)" + N + "        }";
const new3 = "        const sensitive = SensitiveOperationDetector.detectClick(agentId, selector, '')" + N + "        if (sensitive) {" + N + "          // P6: 敏感点击走确认链" + N + "          console.info('[AgentEngine] sensitive click -> requestConfirmation: ' + sensitive + ' selector=' + selector)" + N + "          const confirmed = await SensitiveOperationDetector.requestConfirmation(agentId, sensitive, '', selector)" + N + "          console.info('[AgentEngine] requestConfirmation resolved: ' + confirmed)" + N + "          if (!confirmed) {" + N + "            return this.bcpFail(`sensitive click rejected by user: ${sensitive}`)" + N + "          }" + N + "        }";
if (!c.includes(old3)) { console.error('E3 NOT FOUND'); process.exit(1); }
c = c.replace(old3, new3);

fs.writeFileSync(f, c, 'utf8');
console.log('AgentEngine patched: autoNav=' + c.includes('auto-navigate agent tab') + ' confirmChain=' + c.includes('requestConfirmation'));
