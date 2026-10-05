
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

  console.log('[BCP] Bridge script injected successfully');
})();
`

const HTML2CANVAS_LOADER = `
(function() {
  if (typeof html2canvas !== 'undefined') return;
  var script = document.createElement('script');
  script.src = 'https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js';
  script.onload = function() { console.log('[BCP] html2canvas loaded'); };
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
}

export const JSBridgeInjector = new JSBridgeInjectorImpl()