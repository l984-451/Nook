// no-xhr-if.js — Wraps XMLHttpRequest.open() to block requests matching pattern.
// Usage: no-xhr-if(urlPattern [, propsToMatch])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const urlPattern = args[0] || '';
    const propsToMatch = args[1] || '';

    let urlRe;
    try { urlRe = new RegExp(urlPattern); } catch (e) {
        urlRe = { test: (s) => s.includes(urlPattern) };
    }

    const origOpen = XMLHttpRequest.prototype.open;

    XMLHttpRequest.prototype.open = function(method, url) {
        const urlStr = String(url);
        if (urlRe.test(urlStr)) {
            if (propsToMatch) {
                const checks = propsToMatch.split(/\s+/);
                let match = true;
                for (const check of checks) {
                    const [prop, val] = check.split(':');
                    if (prop === 'method' && val !== undefined && method.toLowerCase() !== val.toLowerCase()) {
                        match = false;
                        break;
                    }
                }
                if (!match) {
                    return origOpen.apply(this, arguments);
                }
            }
            // Block by overriding send to do nothing
            this.send = function() {};
            this.abort = function() {};
            Object.defineProperties(this, {
                readyState: { value: 4, writable: false },
                status: { value: 200, writable: false },
                statusText: { value: 'OK', writable: false },
                responseText: { value: '{}', writable: false },
                response: { value: '{}', writable: false }
            });
            return;
        }
        return origOpen.apply(this, arguments);
    };
})();
