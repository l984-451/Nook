// trusted-replace-xhr-response.js — Replaces text in XMLHttpRequest responses.
// Usage: trusted-replace-xhr-response(pattern, replacement, [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const pattern = args[0] || '';
    const replacement = args[1] || '';
    const urlMatch = args[2] || '';

    if (!pattern) return;

    let patternRe;
    try {
        patternRe = new RegExp(pattern, 'gms');
    } catch (e) {
        patternRe = null;
    }

    let urlRe;
    if (urlMatch) {
        try { urlRe = new RegExp(urlMatch); } catch (e) {
            urlRe = { test: (s) => s.includes(urlMatch) };
        }
    }

    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url) {
        this._nookUrl = String(url);
        return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function() {
        if (urlRe && !urlRe.test(this._nookUrl || '')) {
            return origSend.apply(this, arguments);
        }

        const xhr = this;
        const origOnReady = xhr.onreadystatechange;
        const origOnLoad = xhr.onload;

        function modifyResponse() {
            if (xhr.readyState === 4) {
                try {
                    let text = xhr.responseText;
                    let modified;
                    if (patternRe) {
                        modified = text.replace(patternRe, replacement);
                    } else {
                        modified = text.split(pattern).join(replacement);
                    }
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
