# -*- coding: utf-8 -*-
"""P2 acceptance: create agent via UI, watch LLM loop"""
import subprocess, time

TARGET = '127.0.0.1:15566'

def sh(cmd, wait=0.3):
    r = subprocess.run(['hdc', '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=60)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')

def tap(x, y):
    sh(f'uitest uiInput click {x} {y}')

def activate():
    sh('uitest uiInput keyEvent 2016')

def type_text(x, y, text):
    tap(x, y)
    activate()
    sh(f"uitest uiInput inputText {x} {y} '{text}'", 0.4)

def hilog_agent():
    return sh("\"hilog -x | grep -E 'AgentEngine|LLMClient|BCPEngine' | tail -30\"", 0.2)

# fresh form coords (p2acc2.json): name(801,327) url(801,364) task(801,401) create(800,443)
type_text(801, 327, 't5')
type_text(801, 364, 'https://example.com')
type_text(801, 401, 'open the page and tell me the page title')
tap(800, 443)
print('=== form filled + create clicked, waiting for LLM loop ===')
for i in range(6):
    time.sleep(15)
    out = hilog_agent()
    print(f'--- poll {i+1} ---')
    print(out)
    low = out.lower()
    if 'task completed' in low or 'agent error' in low or 'llm error' in low or 'all steps done' in low:
        break
print('=== final snapshot ===')
sh('snapshot_display -f /data/local/tmp/p2_final.jpeg', 1)
subprocess.run(['hdc', '-t', TARGET, 'file', 'recv', '/data/local/tmp/p2_final.jpeg', r'D:\BrowserOS - KaihongOS\p2_final.jpeg'], capture_output=True, text=True, timeout=30)
print('done')
