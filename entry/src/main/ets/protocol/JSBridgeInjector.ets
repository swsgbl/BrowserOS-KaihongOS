
import { BCPResult } from '../common/Types'
import { IWebviewController } from '../common/IWebviewController'
import { Constants } from '../common/Constants'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'

const BCP_BRIDGE_SCRIPT = `
(function() {
  if (window.__bcp_bridge) return;
  window.__bcp_bridge = true;

  window.__bcp_callbacks = {};
  window.__bcp_callback_id = 0;

  function generateCallbackId() {
    return ++window.__bcp_callback_id;
  }

  window.__bcp_navigate = function(url, callbackId) {
    try {
      window.location.href = url;
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: url, error: null}));
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  window.__bcp_click = function(selector, callbackId) {
    try {
      const el = document.querySelector(selector);
      if (!el) {
        window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: 'Element not found: ' + selector}));
        return;
      }
      el.click();
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: selector, error: null}));
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  window.__bcp_type = function(selector, text, callbackId) {
    try {
      const el = document.querySelector(selector);
      if (!el) {
        window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: 'Element not found: ' + selector}));
        return;
      }
      el.focus();
      el.value = text;
      el.dispatchEvent(new Event('input', {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: text, error: null}));
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  window.__bcp_scroll = function(deltaX, deltaY, callbackId) {
    try {
      window.scrollBy(deltaX, deltaY);
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: JSON.stringify({x: window.scrollX, y: window.scrollY}), error: null}));
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  window.__bcp_get_text = function(callbackId) {
    try {
      const text = document.body.innerText || '';
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: text.substring(0, 50000), error: null}));
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  // P12b: 紧凑 Markdown 快照——clone 后剔除噪音元素，只取可见内容，结构降为 Markdown，省 token。
  // 同步 return 结果（runJavaScript 表达式求值直取），不依赖 registerJavaScriptProxy 回调
  // （该 proxy 在 navigate 换页后会失效——MCP 冷调场景曾致 "arkts_callback is not a function"）
  window.__bcp_snapshot_md = function() {
    try {
      const NOISE = 'script,style,noscript,template,iframe,svg,canvas,form,link,meta';
      const clone = document.body.cloneNode(true);
      clone.querySelectorAll(NOISE).forEach(function(n) { n.remove(); });
      const lines = [];
      function visible(el) {
        const cs = window.getComputedStyle(el);
        if (cs.display === 'none' || cs.visibility === 'hidden') return false;
        return true;
      }
      function walk(node, listPrefix) {
        if (lines.join(String.fromCharCode(10)).length > 30000) return;
        if (node.nodeType === 3) {
          const t = node.textContent.replace(/\\s+/g, ' ').trim();
          if (t) lines.push(listPrefix + t);
          return;
        }
        if (node.nodeType !== 1) return;
        const el = node;
        const tag = el.tagName.toLowerCase();
        if (!visible(el)) return;
        if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
          const t = el.textContent.replace(/\\s+/g, ' ').trim();
          if (t) {
            const level = parseInt(tag.charAt(1), 10);
            let prefix = '';
            for (let k = 0; k < level; k++) prefix += '#';
            lines.push('');
            lines.push(prefix + ' ' + t);
          }
          return;
        }
        if (tag === 'a') {
          const t = el.textContent.replace(/\\s+/g, ' ').trim();
          let href = el.getAttribute('href') || '';
          if (href && !href.startsWith('http')) {
            try { href = new URL(href, location.href).href; } catch(e) { }
          }
          if (t) lines.push(listPrefix + (href ? '[' + t + '](' + href + ')' : t));
          return;
        }
        if (tag === 'button' || (tag === 'input' && (el.type === 'submit' || el.type === 'button'))) {
          const t = (el.value || el.textContent || '').replace(/\\s+/g, ' ').trim();
          if (t) lines.push(listPrefix + '[按钮 ' + t + ']');
          return;
        }
        if (tag === 'img') {
          const alt = el.getAttribute('alt') || '';
          if (alt.trim()) lines.push(listPrefix + '[图: ' + alt.trim() + ']');
          return;
        }
        if (tag === 'li') {
          const t = el.textContent.replace(/\\s+/g, ' ').trim();
          if (t) lines.push(listPrefix + '- ' + t);
          return;
        }
        if (tag === 'table') {
          el.querySelectorAll('tr').forEach(function(tr) {
            const cells = [];
            tr.querySelectorAll('th,td').forEach(function(c) {
              cells.push(c.textContent.replace(/\\s+/g, ' ').trim());
            });
            if (cells.length) lines.push('| ' + cells.join(' | ') + ' |');
          });
          return;
        }
        for (const child of el.childNodes) walk(child, listPrefix);
      }
      walk(clone, '');
      let md = lines.join(String.fromCharCode(10)).replace(/\\n{3,}/g, String.fromCharCode(10) + String.fromCharCode(10));
      if (md.length > 30000) md = md.substring(0, 30000) + String.fromCharCode(10) + '...[截断]';
      return md;
    } catch(e) {
      return '__SNAP_ERR__' + e.message;
    }
  };

  window.__bcp_wait_for = function(selector, timeout, callbackId) {
    try {
      const el = document.querySelector(selector);
      if (el) {
        window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: selector, error: null}));
        return;
      }
      const startTime = Date.now();
      const interval = setInterval(function() {
        const el = document.querySelector(selector);
        if (el) {
          clearInterval(interval);
          window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: selector, error: null}));
        } else if (Date.now() - startTime > timeout) {
          clearInterval(interval);
          window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: 'Timeout waiting for: ' + selector}));
        }
      }, 100);
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  window.__bcp_snapshot = function(callbackId) {
    try {
      const SEMANTIC_TAGS = ['a','button','input','form','img','table','div','section','nav','header','footer','main','article','ul','ol','li','p','h1','h2','h3','h4','h5','h6','span','label','select','textarea'];
      const SEMANTIC_ATTRS = ['href','src','alt','title','type','name','value','placeholder','role','aria-label'];

      function buildSnapshot(node) {
        if (node.nodeType === 3) {
          const text = node.textContent.trim();
          if (text) return {tag: '#text', attrs: {}, text: text.substring(0, 200)};
          return null;
        }
        if (node.nodeType !== 1) return null;

        const tag = node.tagName.toLowerCase();
        if (!SEMANTIC_TAGS.includes(tag)) return null;

        const attrs = {};
        for (const attr of SEMANTIC_ATTRS) {
          if (node.hasAttribute(attr)) {
            attrs[attr] = node.getAttribute(attr);
          }
        }

        const children = [];
        for (const child of node.childNodes) {
          const childSnapshot = buildSnapshot(child);
          if (childSnapshot) children.push(childSnapshot);
        }

        return {tag: tag, attrs: attrs, children: children};
      }

      const snapshot = buildSnapshot(document.body);
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: JSON.stringify(snapshot), error: null}));
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  window.__bcp_screenshot = function(quality, callbackId) {
    try {
      if (typeof html2canvas === 'undefined') {
        window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: 'html2canvas not loaded'}));
        return;
      }
      const scale = quality === 'low' ? 0.3 : quality === 'medium' ? 0.6 : 1.0;
      html2canvas(document.body, {scale: scale, logging: false, useCORS: true}).then(function(canvas) {
        const dataUrl = canvas.toDataURL('image/jpeg', 0.7);
        window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: dataUrl, error: null}));
      }).catch(function(err) {
        window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: err.message}));
      });
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  window.__bcp_back = function(callbackId) {
    try {
      history.back();
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: null, error: null}));
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };

  window.__bcp_forward = function(callbackId) {
    try {
      history.forward();
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: true, data: null, error: null}));
    } catch(e) {
      window.__bcp_arkts_callback(callbackId, JSON.stringify({success: false, data: null, error: e.message}));
    }
  };


  // P24a: Agent 运行辉光 overlay + 底部停止钮(对标上游 glow.content)
  // start=注入 fixed 覆盖层(inset box-shadow 橙脉冲 3s 循环) + 48px 红圆停止钮;
  // 停止钮 onclick 置 window.__bcp_glow_stop_requested=true(同步标记, ArkTS 侧轮询)
  window.__bcp_glow_stop_requested = false;

  window.__bcp_glow_start = function() {
    try {
      if (document.getElementById('browseros-glow-overlay')) return;
      var ov = document.createElement('div');
      ov.id = 'browseros-glow-overlay';
      ov.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483646;'
        + 'animation:__bcp_glow_pulse 3s ease-in-out infinite;'
        + 'box-shadow:inset 0 0 24px 6px rgba(251,102,24,0.55);';
      var st = document.createElement('style');
      st.id = 'browseros-glow-style';
      st.textContent = '@keyframes __bcp_glow_pulse{0%,100%{box-shadow:inset 0 0 24px 6px rgba(251,102,24,0.55)}'
        + '50%{box-shadow:inset 0 0 42px 12px rgba(251,102,24,0.9)}}';
      document.documentElement.appendChild(st);
      document.documentElement.appendChild(ov);

      var btn = document.createElement('div');
      btn.id = 'browseros-glow-stop';
      btn.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);'
        + 'width:48px;height:48px;border-radius:50%;background:#DC2626;'
        + 'box-shadow:0 4px 14px rgba(0,0,0,0.35);cursor:pointer;z-index:2147483647;'
        + 'pointer-events:auto;display:flex;align-items:center;justify-content:center;';
      btn.title = 'Stop agent';
      var sq = document.createElement('div');
      sq.style.cssText = 'width:14px;height:14px;background:#FFFFFF;border-radius:3px;';
      btn.appendChild(sq);
      btn.addEventListener('click', function() {
        window.__bcp_glow_stop_requested = true;
        try { window.__bcp_glow_stop(); } catch (e) { }
      });
      document.documentElement.appendChild(btn);
    } catch (e) {
      console.warn('[BCP] glow_start error: ' + e);
    }
  };

  window.__bcp_glow_stop = function() {
    try {
      var ov = document.getElementById('browseros-glow-overlay');
      if (ov) ov.remove();
      var btn = document.getElementById('browseros-glow-stop');
      if (btn) btn.remove();
      var st = document.getElementById('browseros-glow-style');
      if (st) st.remove();
    } catch (e) {
      console.warn('[BCP] glow_stop error: ' + e);
    }
  };

  console.info('[BCP] Bridge script injected successfully');
})();
`

/** P33-A: 选中文本捕获脚本(对标上游 selectedTextStorage) — mouseup 取 window.getSelection,
 * 截 5000 字,连同 pageUrl/pageTitle/timestamp 存 window.__bcp_sel(JSON 字符串);
 * 选区清空时同步清除,侧栏发送前读取拼进聊天上下文 */
const SEL_CAPTURE_SCRIPT = `
(function() {
  if (window.__bcp_sel_installed) return;
  window.__bcp_sel_installed = true;
  document.addEventListener('mouseup', function() {
    try {
      var sel = window.getSelection ? window.getSelection().toString() : '';
      sel = (sel || '').trim();
      if (sel.length > 0) {
        window.__bcp_sel = JSON.stringify({
          text: sel.slice(0, 5000),
          pageUrl: location.href,
          pageTitle: document.title || '',
          timestamp: Date.now()
        });
      } else {
        window.__bcp_sel = null;
      }
    } catch (e) { }
  });
  console.info('[BCP][P33] selection capture installed');
})();
`

const HTML2CANVAS_LOADER = `
(function() {
  if (typeof html2canvas !== 'undefined') return;
  var script = document.createElement('script');
  script.src = 'https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js';
  script.onload = function() { console.info('[BCP] html2canvas loaded'); };
  script.onerror = function() { console.error('[BCP] html2canvas load failed'); };
  document.head.appendChild(script);
})();
`

class JSBridgeInjectorImpl {
  private injectedWebViews: Set<string> = new Set()
  private pendingCallbacks: Map<number, (result: BCPResult) => void> = new Map()
  private callbackCounter: number = 0
  private currentWebView: IWebviewController | null = null

  setWebView(webviewController: IWebviewController): void {
    this.currentWebView = webviewController
  }

  injectBridge(webviewController: IWebviewController): void {
    try {
      webviewController.runJavaScript(BCP_BRIDGE_SCRIPT)
      webviewController.runJavaScript(HTML2CANVAS_LOADER)
      webviewController.runJavaScript(SEL_CAPTURE_SCRIPT)
    } catch (e) {
      ErrorHandler.handle(new AppError(ErrorCodes.BCP_001, `Bridge injection failed: ${e}`))
    }
  }

  isInjected(webviewId: string): boolean {
    return this.injectedWebViews.has(webviewId)
  }

  markInjected(webviewId: string): void {
    this.injectedWebViews.add(webviewId)
  }

  clearInjected(webviewId: string): void {
    this.injectedWebViews.delete(webviewId)
  }

  registerCallback(callback: (result: BCPResult) => void): number {
    const id = ++this.callbackCounter
    this.pendingCallbacks.set(id, callback)
    return id
  }

  resolveCallback(callbackId: number, result: BCPResult): void {
    const callback = this.pendingCallbacks.get(callbackId)
    if (callback) {
      callback(result)
      this.pendingCallbacks.delete(callbackId)
    }
  }

  getBridgeScript(): string {
    return BCP_BRIDGE_SCRIPT
  }

  getHtml2CanvasLoader(): string {
    return HTML2CANVAS_LOADER
  }

  /** P24a: 辉光脚本片段(随桥注入, 同 BCP_BRIDGE_SCRIPT 常量字符串) */
  glowStart(): string {
    return 'window.__bcp_glow_start ? window.__bcp_glow_start() : (function(){return 1;})()'
  }

  glowStop(): string {
    return 'window.__bcp_glow_stop ? window.__bcp_glow_stop() : (function(){return 1;})()'
  }

  /** P24a: 停止标记查询脚本(runJavaScript 求值 true/false) */
  glowStopRequested(): string {
    return 'window.__bcp_glow_stop_requested === true'
  }

  /** P33-A: 读取页面选中文本(JSON 字符串或 null),runJavaScript 表达式求值 */
  readSelection(): string {
    return 'JSON.stringify(window.__bcp_sel || null)'
  }
}

export const JSBridgeInjector = new JSBridgeInjectorImpl()