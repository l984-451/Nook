// json-prune-xhr-response.js — Intercepts XHR responses and prunes JSON keys.
// Usage: json-prune-xhr-response(keyPaths, [propsToMatch], [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const rawKeys = (args[0] || '').split(/\s+/);
    const propsToMatch = args[1] || '';
    let urlPattern = '';
    for (let i = 1; i < args.length; i++) {
        if (args[i] && args[i].startsWith('url:')) {
            urlPattern = args[i].substring(4);
        }
    }

    let urlRe;
    if (urlPattern) {
        try { urlRe = new RegExp(urlPattern); } catch (e) {
            urlRe = { test: (s) => s.includes(urlPattern) };
        }
    }

    const pruneKeys = rawKeys.map(k => k.split('.'));

    function shouldPrune(obj) {
        if (!propsToMatch || propsToMatch.startsWith('url:')) return true;
        const checks = propsToMatch.split(/\s+/);
        for (const check of checks) {
            if (check.startsWith('url:')) continue;
            const [path, val] = check.split(':');
            let current = obj;
            for (const part of path.split('.')) {
                if (current == null || typeof current !== 'object') return false;
                if (!(part in current)) return false;
                current = current[part];
            }
            if (val !== undefined && String(current) !== val) return false;
        }
        return true;
    }

    function pruneObject(obj) {
        if (typeof obj !== 'object' || obj === null) return obj;
        if (!shouldPrune(obj)) return obj;
        for (const keyPath of pruneKeys) {
            let current = obj;
            for (let i = 0; i < keyPath.length - 1; i++) {
                const part = keyPath[i];
                if (part === '[-]' && Array.isArray(current)) {
                    const remaining = keyPath.slice(i + 1);
                    for (const item of current) {
                        pruneObject(item);
                    }
                    current = null;
                    break;
                }
                if (current == null || typeof current !== 'object') break;
                current = current[part];
            }
            if (current != null && typeof current === 'object') {
                const lastKey = keyPath[keyPath.length - 1];
                if (lastKey in current) {
                    delete current[lastKey];
                }
            }
        }
        return obj;
    }

    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url) {
        this._nookPruneUrl = String(url);
        return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function() {
        if (urlRe && !urlRe.test(this._nookPruneUrl || '')) {
            return origSend.apply(this, arguments);
        }

        const xhr = this;
        const origOnReady = xhr.onreadystatechange;
        const origOnLoad = xhr.onload;

        function modifyResponse() {
            if (xhr.readyState === 4) {
                try {
                    let text = xhr.responseText;
                    let json = JSON.parse(text);
                    json = pruneObject(json);
                    const modified = JSON.stringify(json);
                    if (modified !== text) {
                        Object.defineProperty(xhr, 'responseText', { value: modified, writable: false, configurable: true });
                        Object.defineProperty(xhr, 'response', { value: modified, writable: false, configurable: true });
                    }
                } catch (e) {}
            }
        }

        if (origOnReady) {
            xhr.onreadystatechange = function() {
                modifyResponse();
                return origOnReady.apply(this, arguments);
            };
        }
        if (origOnLoad) {
            xhr.onload = function() {
                modifyResponse();
                return origOnLoad.apply(this, arguments);
            };
        }

        xhr.addEventListener('load', modifyResponse);
        return origSend.apply(this, arguments);
    };
})();
