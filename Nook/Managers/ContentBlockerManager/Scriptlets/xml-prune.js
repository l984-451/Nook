// xml-prune.js — Prunes DASH ad segments from XML manifests (MPD).
// Intercepts fetch/XHR responses with XML content, removes elements matching selector.
// Usage: xml-prune(elementSelector, [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const elementSelector = args[0] || '';
    const urlPattern = args[1] || '';

    if (!elementSelector) return;

    let urlRe;
    if (urlPattern) {
        try { urlRe = new RegExp(urlPattern); } catch (e) {
            urlRe = { test: (s) => s.includes(urlPattern) };
        }
    }

    function urlMatches(url) {
        if (!urlRe) return true;
        return urlRe.test(url);
    }

    function isXmlContent(url, contentType) {
        if (contentType && (contentType.includes('xml') || contentType.includes('mpd'))) return true;
        if (url.includes('.mpd') || url.includes('.xml')) return true;
        return false;
    }

    function pruneXML(text) {
        if (!text || !text.trimStart().startsWith('<')) return text;
        try {
            const parser = new DOMParser();
            const doc = parser.parseFromString(text, 'text/xml');
            if (doc.querySelector('parsererror')) return text;

            // Support both CSS selectors and simple tag names
            const selectors = elementSelector.split(/\s*,\s*/);
            let modified = false;
            for (const sel of selectors) {
                const trimSel = sel.trim();
                if (!trimSel) continue;

                // Try XPath if it starts with //
                if (trimSel.startsWith('//')) {
                    try {
                        const xpResult = doc.evaluate(trimSel, doc, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
                        for (let i = xpResult.snapshotLength - 1; i >= 0; i--) {
                            const node = xpResult.snapshotItem(i);
                            if (node && node.parentNode) {
                                node.parentNode.removeChild(node);
                                modified = true;
                            }
                        }
                    } catch (e) {}
                } else {
                    // CSS selector or tag name
                    const elements = doc.querySelectorAll(trimSel);
                    for (const el of elements) {
                        if (el.parentNode) {
                            el.parentNode.removeChild(el);
                            modified = true;
                        }
                    }
                }
            }

            if (modified) {
                const serializer = new XMLSerializer();
                return serializer.serializeToString(doc);
            }
        } catch (e) {}
        return text;
    }

    // Intercept fetch
    const originalFetch = window.fetch;
    window.fetch = new Proxy(originalFetch, {
        apply(target, thisArg, argumentsList) {
            const input = argumentsList[0];
            let url = '';
            if (typeof input === 'string') url = input;
            else if (input instanceof Request) url = input.url;
            else if (input instanceof URL) url = input.href;

            if (!urlMatches(url)) {
                return Reflect.apply(target, thisArg, argumentsList);
            }

            return Reflect.apply(target, thisArg, argumentsList).then(response => {
                const ct = response.headers.get('content-type') || '';
                if (isXmlContent(url, ct)) {
                    const clone = response.clone();
                    return clone.text().then(text => {
                        const pruned = pruneXML(text);
                        if (pruned !== text) {
                            const newHeaders = new Headers(response.headers);
                            newHeaders.delete('content-length');
                            return new Response(pruned, {
                                status: response.status,
                                statusText: response.statusText,
                                headers: newHeaders
                            });
                        }
                        return response;
                    });
                }
                return response;
            });
        }
    });

    // Intercept XHR
    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url) {
        this._nookXmlUrl = String(url);
        return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function() {
        const reqUrl = this._nookXmlUrl || '';
        if (!urlMatches(reqUrl)) {
            return origSend.apply(this, arguments);
        }

        const xhr = this;
        const origOnReady = xhr.onreadystatechange;
        const origOnLoad = xhr.onload;

        function modifyResponse() {
            if (xhr.readyState === 4) {
                try {
                    const ct = xhr.getResponseHeader('content-type') || '';
                    if (!isXmlContent(reqUrl, ct)) return;
                    const text = xhr.responseText;
                    const pruned = pruneXML(text);
                    if (pruned !== text) {
                        Object.defineProperty(xhr, 'responseText', { value: pruned, writable: false, configurable: true });
                        Object.defineProperty(xhr, 'response', { value: pruned, writable: false, configurable: true });
                    }
                } catch (e) {}
            }
        }

        if (origOnReady) {
            xhr.onreadystatechange = function() { modifyResponse(); return origOnReady.apply(this, arguments); };
        }
        if (origOnLoad) {
            xhr.onload = function() { modifyResponse(); return origOnLoad.apply(this, arguments); };
        }
        xhr.addEventListener('load', modifyResponse);
        return origSend.apply(this, arguments);
    };
})();
