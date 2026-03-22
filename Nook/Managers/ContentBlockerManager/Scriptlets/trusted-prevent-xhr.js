// trusted-prevent-xhr.js — Block XHR with custom response.
// Usage: trusted-prevent-xhr(urlPattern, [status], [body])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const urlPattern = args[0] || '';
    const status = parseInt(args[1], 10) || 200;
    const body = args[2] || '';
    if (!urlPattern) return;

    let urlRe;
    try { urlRe = new RegExp(urlPattern); } catch(e) { urlRe = { test: (s) => s.includes(urlPattern) }; }

    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url) {
        this._nookPreventUrl = String(url);
        this._nookPreventMethod = method;
        return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function() {
        if (urlRe.test(this._nookPreventUrl || '')) {
            const xhr = this;
            Object.defineProperty(xhr, 'readyState', { value: 4, writable: false, configurable: true });
            Object.defineProperty(xhr, 'status', { value: status, writable: false, configurable: true });
            Object.defineProperty(xhr, 'statusText', { value: 'OK', writable: false, configurable: true });
            Object.defineProperty(xhr, 'responseText', { value: body, writable: false, configurable: true });
            Object.defineProperty(xhr, 'response', { value: body, writable: false, configurable: true });
            setTimeout(() => {
                if (xhr.onreadystatechange) xhr.onreadystatechange();
                if (xhr.onload) xhr.onload();
                xhr.dispatchEvent(new Event('load'));
                xhr.dispatchEvent(new Event('loadend'));
            }, 0);
            return;
        }
        return origSend.apply(this, arguments);
    };
})();
