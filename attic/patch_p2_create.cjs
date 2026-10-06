# -*- coding: utf-8 -*-
"""P2 patch part 3: createAgent always auto-run + NeoDashboardPage UI."""
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

AE = r'D:\BrowserOS - KaihongOS\entry\src\main\ets\service\AgentEngine.ets'
patch(AE, [
    ("""    // P2: 配置齐全则自动开跑（异步，不阻塞 UI）
    const cfg = ConfigManager.get()
    if (cfg.llmBaseUrl && cfg.llmBaseUrl.length > 0) {
      this.runAgentTask(agentId)
    } else {
      console.info('[AgentEngine] LLM not configured, agent stays idle: ' + agentId)
    }

    return config""",
     """    // P2: 创建即自动开跑（异步，不阻塞 UI）；未配置 LLM 时由 runAgentTask 立即置 ERROR
    this.runAgentTask(agentId)

    return config"""),
])
print('AGENT CREATE FIXED')
