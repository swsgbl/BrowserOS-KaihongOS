import os, re, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = r'D:\BrowserOS - KaihongOS'
# Check rate limiting
for f in ['HttpMcpTransport.ets', 'WsMcpTransport.ets', 'McpRateLimiter.ets']:
    p = os.path.join(ROOT, 'entry/src/main/ets/service', f)
    if os.path.exists(p):
        t = open(p, encoding='utf-8').read()
        has_rl = 'McpRateLimiter' in t or 'RateLimit' in t
        print('%s: rate_limit=%s' % (f, has_rl))

# Check cookie injection
for f in ['LoginStateManager.ets', 'BrowserShell.ets', 'ImportWizardPage.ets', 'ImportWizardPage.ets']:
    for sub in ['service', 'pages']:
        p = os.path.join(ROOT, 'entry/src/main/ets', sub, f)
        if os.path.exists(p):
            t = open(p, encoding='utf-8').read()
            has_cookie = any(k in t for k in ['CookieManager', 'injectCookies', 'cookieManager', 'webCookie'])
            print('%s/%s: cookie_inject=%s' % (sub, f, has_cookie))

# Search all files for cookie injection
for root, dirs, files in os.walk(os.path.join(ROOT, 'entry/src/main/ets')):
    for fn in files:
        if fn.endswith('.ets'):
            p = os.path.join(root, fn)
            t = open(p, encoding='utf-8', errors='replace').read()
            if any(k in t for k in ['CookieManager', 'injectCookies', 'webCookie']):
                print('FOUND cookie in: %s' % os.path.relpath(p, ROOT))
