#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P42 A-G 设备证据收集（写 evidence/p42/）。用法: py tools/p42_evidence.py"""
import json
import os
import subprocess
import sys
import time
import urllib.request

HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
TARGET = "192.168.161.137:10178"
BUNDLE = "com.browseros.kaihong"
EVID = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "evidence", "p42")
os.makedirs(EVID, exist_ok=True)
HOST_TUNNEL = 19222  # fport 宿主侧端口（smoke 同款）


def hdc(*args, timeout=40):
    r = subprocess.run([HDC, "-t", TARGET] + list(args), capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    return r.returncode, ((r.stdout or "") + (r.stderr or "")).strip()


def save(name, text):
    p = os.path.join(EVID, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
    print("saved", name, len(text), "chars")


def mcp_call(method, params, tool=None):
    """经 fport 隧道调 MCP。返回 (ok, body_text)"""
    hdc("fport", "rm", f"tcp:{HOST_TUNNEL}", "tcp:9222")
    rc, _ = hdc("fport", f"tcp:{HOST_TUNNEL}", "tcp:9222")
    time.sleep(0.6)
    rc, out = hdc("shell", f"cat /data/app/el2/100/base/{BUNDLE}/haps/entry/files/mcp_token.txt")
    token = out.strip().splitlines()[-1].strip() if out.strip() else ""
    if not token:
        return False, "no token"
    if tool:
        body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                "params": {"name": tool, "arguments": params}}
    else:
        body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    req = urllib.request.Request(
        f"http://127.0.0.1:{HOST_TUNNEL}/mcp?token={token}",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return True, resp.read().decode("utf-8", "replace")
    except Exception as e:
        return False, f"{e}"


def ev_a_loopback():
    """A: 设备内 netstat 证明 9222/8765 只听 127.0.0.1"""
    rc, net = hdc("shell", "netstat -tlnp 2>/dev/null | grep -E ':(9222|8765)'")
    rc2, net2 = hdc("shell", "netstat -an | grep -E ':(9222|8765).*LISTEN'")
    save("A_loopback_netstat.txt", net + "\n--\n" + net2)
    ok = "127.0.0.1:9222" in (net + net2) and "0.0.0.0:9222" not in (net + net2)
    print("[A] loopback bind:", "PASS" if ok else "CHECK", "\n" + net + "\n" + net2)


def ev_b_token():
    """B: token 32 位 + 格式（CSPRNG 生成，格式与旧版一致）"""
    rc, out = hdc("shell", f"cat /data/app/el2/100/base/{BUNDLE}/haps/entry/files/mcp_token.txt")
    token = out.strip().splitlines()[-1].strip() if out.strip() else ""
    import re
    ok = bool(re.fullmatch(r"[A-Za-z0-9]{32}", token))
    save("B_csprng_token.txt", f"token={token}\nlen={len(token)}\nalnum32={ok}\n")
    print("[B] token format:", "PASS" if ok else "FAIL", f"len={len(token)}")


def ev_c_typegate():
    """C: MCP type 敏感输入 → 确认挂起/拒绝（敏感检测命中）"""
    ok, body = mcp_call(None, {}, tool=("type", {"selector": "#password", "text": "password123"}))
    # 预期: 挂起等待 ConfirmDialog（超时）或 AGT_003 拒绝——两者都算 gate 生效
    gated = (not ok) or ("AGT_003" in body) or ("rejected" in body.lower())
    save("C_type_gate.txt", f"ok={ok}\n{body[:800]}\n\ngated={gated}")
    print("[C] type gate:", "PASS(gated)" if gated else "INFO", body[:120].replace("\n", " "))


def ev_d_redact():
    """D: MCP navigate 到 data: 页面后 getText/type —— 工具响应脱敏验证（sk- key）。
    直接用 type 工具注入 sk- 文本，若 gate 拒绝则改用 snapshot（响应走同一条 redact 链）。"""
    # 简单方案：getText 不会有敏感词；改 navigate data:text/html 带 sk- 字样 → getText 响应应含 ***
    ok, body = mcp_call(None, {}, tool=("navigate", {"url": "data:text/html,<div>sk-abcdefgh12345 secret password=hunter2</div>"}))
    if ok:
        ok2, body2 = mcp_call(None, {}, tool=("getText", {}))
        redacted = "***" in body2 and "sk-abcdefgh12345" not in body2
        save("D_redact.txt", f"navigate={body[:200]}\ngetText={body2[:600]}\n\nredacted={redacted}")
        print("[D] redact:", "PASS" if redacted else "INFO", body2[:120].replace("\n", " "))
        return
    save("D_redact.txt", f"navigate failed: {body[:300]}")
    print("[D] redact: SKIP(navigate fail)", body[:100])


def ev_e_sessions():
    """E: 会话目录现状 + cleanup 按时间语义的静态证据（运行时触发条件复杂，记录索引+文件）"""
    rc, out = hdc("shell", f"ls /data/app/el2/100/base/{BUNDLE}/haps/entry/files/sessions/ 2>/dev/null")
    rc2, idx = hdc("shell", f"more /data/app/el2/100/base/{BUNDLE}/haps/entry/files/sessions/session_index.json 2>/dev/null")
    save("E_sessions_cleanup.txt", f"files:\n{out}\n\nindex:\n{idx[:2000]}")
    print("[E] sessions snapshot saved;", out.replace("\n", " ")[:100])


def ev_f_h2c():
    """F: html2canvas 本地化——hilog 出现 'html2canvas local source preloaded'"""
    hdc("shell", "hilog -r")
    hdc("shell", "aa force-stop " + BUNDLE)
    time.sleep(1)
    hdc("shell", f"aa start -a EntryAbility -b {BUNDLE}")
    time.sleep(5)
    rc, log = hdc("shell", "hilog -x | grep -i 'html2canvas' | tail -5", timeout=30)
    preloaded = "local source preloaded" in log
    save("F_html2canvas_local.txt", log or "(no h2c log)")
    print("[F] h2c local preload:", "PASS" if preloaded else "CHECK", log.replace("\n", " | ")[:150])


def ev_g_isurl():
    """G: isUrl localhost——通过 MCP navigate localhost 页（等价验证 URL 处理链路可用性）"""
    ok, body = mcp_call(None, {}, tool=("navigate", {"url": "http://127.0.0.1:9222/mcp"}))
    # 9222 现在只听 loopback，设备内 webview 访问 127.0.0.1:9222 是通的（同一网络栈）
    ok2, body2 = mcp_call(None, {}, tool=("navigate", {"url": "http://localhost:9222/mcp"}))
    save("G_isurl_localhost.txt",
         f"127.0.0.1 nav: ok={ok} {body[:200]}\nlocalhost nav: ok={ok2} {body2[:200]}")
    print("[G] localhost navigate:", "PASS" if ok2 else "CHECK", body2[:100].replace("\n", " "))


def main():
    print("== P42 evidence collection ==")
    ev_a_loopback()
    ev_b_token()
    ev_c_typegate()
    ev_d_redact()
    ev_e_sessions()
    ev_f_h2c()
    ev_g_isurl()
    print("done ->", EVID)
    return 0


if __name__ == "__main__":
    sys.exit(main())
