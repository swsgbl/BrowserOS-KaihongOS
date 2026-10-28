import sys, json, time
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)
JS = "JSON.stringify({n:document.querySelectorAll('*').length,t:document.title})"
r = call_tool(qs, sid, 'evaluate_in_page', {'expression': JS}, timeout=60)
print(result_text(r)[:700])
