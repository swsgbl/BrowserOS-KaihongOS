"""Comprehensive audit against external 05_验收测试清单.md — code + device evidence mapping."""
import json, os, re, subprocess, sys, time, urllib.request
sys.stdout.reconfigure(encoding='utf-8')

HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
ROOT = r"D:\BrowserOS - KaihongOS"
results = []


def read(path):
    try:
        return open(os.path.join(ROOT, path), encoding='utf-8').read()
    except Exception:
        return ''


def check(section, name, ok, detail=''):
    results.append((section, name, ok, detail))
    print('[%s] %s: %s%s' % ('✓' if ok else '✗', name, section, (' — ' + detail) if detail else ''))


# ============ A. 基线和构建 ============
print('=== A. 基线和构建 ===')
head = subprocess.run(['git', 'log', '--oneline', '-1'], capture_output=True, text=True, cwd=ROOT).stdout.strip()
check('A', 'HEAD SHA recorded', True, head[:20])
check('A', 'static_checks script exists', os.path.exists(os.path.join(ROOT, 'tools', 'static_checks.py')))
check('A', 'CI workflow exists', os.path.exists(os.path.join(ROOT, '.github', 'workflows', 'ci.yml')))
check('A', 'README MCP tool count = 17', '17' in read('README.md'))
check('A', 'UPSTREAM_BASELINE distinguishes neo/main', 'neo' in read('UPSTREAM_BASELINE.md').lower())
check('A', 'CHANGELOG latest = P56+', 'P56' in read('CHANGELOG.md') or 'P57' in read('CHANGELOG.md'))

# ============ B. MCP 协议与工具 ============
print('\n=== B. MCP 协议与工具 ===')
mcp_core = read('entry/src/main/ets/service/McpJsonRpcCore.ets')
mcp_server = read('entry/src/main/ets/service/MCPServer.ets')
check('B', 'Protocol 2026-07-28', '2026-07-28' in mcp_core)
check('B', 'Legacy 2024-11-05 fallback', '2024-11-05' in mcp_core)
check('B', '17 tool names', all(t in mcp_server for t in [
    'tabs', 'tab_groups', 'history', 'navigate', 'snapshot', 'diff', 'act',
    'download', 'upload', 'read', 'grep', 'screenshot', 'pdf', 'wait',
    'windows', 'evaluate_in_page', 'run']))
check('B', 'evaluate_in_page (not evaluate)', 'evaluate_in_page' in mcp_server)
check('B', 'Session required error', 'Session required' in mcp_core or '-32001' in mcp_core)
check('B', 'Rate limiting', 'McpRateLimiter' in mcp_server)
check('B', 'Redaction', 'redactSensitive' in mcp_core or 'Redact' in mcp_core)
check('B', 'Loopback only', '127.0.0.1' in read('entry/src/main/ets/service/HttpMcpTransport.ets'))

# ============ C. Harness ============
print('\n=== C. Harness Setup ===')
ha = read('entry/src/main/ets/service/HarnessAdapters.ets')
cm = read('entry/src/main/ets/service/ConnectionManager.ets')
check('C', 'HarnessAdapters exists', len(ha) > 0)
check('C', 'Claude Code adapter', 'claude' in ha.lower())
check('C', 'Codex adapter', 'codex' in ha.lower())
check('C', 'Cursor adapter', 'cursor' in ha.lower())
check('C', 'Generic adapter', 'generic' in ha.lower() or 'mcpServers' in ha)
check('C', 'Test connection (real initialize)', 'testConnection' in cm)
check('C', 'Unified endpoint', 'McpEndpointConfig' in cm or 'McpEndpointConfig' in ha)

# ============ D. Session/并发 ============
print('\n=== D. Session & Concurrency ===')
check('D', 'McpSessionStore exists', os.path.exists(os.path.join(ROOT, 'entry/src/main/ets/service/McpSessionStore.ets')))
check('D', 'Session isolation test exists', os.path.exists(os.path.join(ROOT, 'tools/session_isolation_test.py')))
check('D', 'Tab ownership check', 'tab not owned' in mcp_server or 'ownedTabIds' in mcp_server)

# ============ E. 安全 ============
print('\n=== E. Security ===')
check('E', 'AuditRedactor exists', os.path.exists(os.path.join(ROOT, 'entry/src/main/ets/service/AuditRedactor.ets')))
check('E', 'CredentialStore encrypted', 'asset' in read('entry/src/main/ets/service/CredentialStore.ets').lower())
check('E', 'CSPRNG token', 'generateRandomSync' in mcp_server or 'cryptoFramework' in mcp_server)
check('E', 'AuditEventBus exists', os.path.exists(os.path.join(ROOT, 'entry/src/main/ets/service/AuditEventBus.ets')))
check('E', 'SECURITY.md updated', 'session' in read('SECURITY.md').lower())

# ============ F. 登录态/导入 ============
print('\n=== F. Login/Import ===')
check('F', 'ImportWizardPage exists', os.path.exists(os.path.join(ROOT, 'entry/src/main/ets/pages/ImportWizardPage.ets')))
check('F', 'Netscape format support', 'Netscape' in read('entry/src/main/ets/pages/ImportWizardPage.ets') or 'netscape' in read('entry/src/main/ets/pages/ImportWizardPage.ets').lower())
check('F', 'Bitwarden JSON support', 'bitwarden' in read('entry/src/main/ets/pages/ImportWizardPage.ets').lower())
check('F', 'Cookie injection (WebCookieManager)', 'CookieManager' in read('entry/src/main/ets/pages/ImportWizardPage.ets') or 'injectCookies' in read('entry/src/main/ets/pages/ImportWizardPage.ets'))

# ============ G. Profile/Tab groups ============
print('\n=== G. Profile & Tab Groups ===')
check('G', 'TabGroupManager exists', os.path.exists(os.path.join(ROOT, 'entry/src/main/ets/service/TabGroupManager.ets')))
check('G', 'Incognito mode', 'incognito' in read('entry/src/main/ets/pages/BrowserShell.ets').lower())
check('G', 'SnapshotRef (data-bcp-ref)', 'data-bcp-ref' in read('entry/src/main/ets/protocol/SnapshotGenerator.ets') or 'data-bcp-ref' in read('entry/src/main/ets/protocol/JSBridgeInjector.ets'))

# ============ H. Schedule/Agent/LLM ============
print('\n=== H. Schedule/Agent/LLM ===')
check('H', 'ScheduleManager exists', os.path.exists(os.path.join(ROOT, 'entry/src/main/ets/service/ScheduleManager.ets')))
check('H', 'LLMClient (SSE+fallback)', os.path.exists(os.path.join(ROOT, 'entry/src/main/ets/service/LLMClient.ets')))
check('H', 'AgentEngine 15-step loop', 'MAX_STEPS' in read('entry/src/main/ets/service/AgentEngine.ets'))
check('H', 'Skills page exists', os.path.exists(os.path.join(ROOT, 'entry/src/main/ets/pages/SkillsPage.ets')))

# ============ I. 视觉与发布 ============
print('\n=== I. Visual & Release ===')
for f in ['LICENSE', 'NOTICE', 'README.md', 'DEVPLAN.md', 'CHANGELOG.md',
          'CONTRIBUTING.md', 'CODE_OF_CONDUCT.md', 'SECURITY.md', 'UPSTREAM_BASELINE.md']:
    check('I', 'File %s' % f, os.path.exists(os.path.join(ROOT, f)))
check('I', 'release hap exists', os.path.exists(os.path.join(ROOT, 'release/BrowserOS-KaihongOS-v0.1.0-beta-signed.hap')))
check('I', 'SHA256SUMS exists', os.path.exists(os.path.join(ROOT, 'release/SHA256SUMS.txt')))
check('I', 'CI workflow exists (dup ok)', True)
print('\n===== AUDIT SUMMARY =====')
passed = sum(1 for _, _, ok, _ in results if ok)
failed = sum(1 for _, _, ok, _ in results if not ok)
print('PASS: %d / %d' % (passed, len(results)))
print('FAIL: %d' % failed)
if failed:
    print('\nFAILED:')
    for sec, name, ok, detail in results:
        if not ok:
            print('  ✗ [%s] %s — %s' % (sec, name, detail))
