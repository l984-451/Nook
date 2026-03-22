// no-window-open-if.js (nowoif) — Prevents window.open() calls matching a URL pattern.
// Usage: no-window-open-if([pattern], [delay], [decoy])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const needle = args[0] || '';
    const delay = parseInt(args[1]) || 0;
    const decoy = args[2] || '';

    let needleRe;
    if (needle) {
        try { needleRe = new RegExp(needle); } catch (e) {
            needleRe = { test: (s) => s.includes(needle) };
        }
    }

    const origOpen = window.open;
    window.open = new Proxy(origOpen, {
        apply(target, thisArg, argumentsList) {
            const url = String(argumentsList[0] || '');
            if (!needle || (needleRe && needleRe.test(url))) {
                // Return a fake window object to prevent errors
                return {
                    closed: false,
                    close() { this.closed = true; },
                    focus() {},
                    blur() {},
                    location: { href: url, replace() {} },
                    document: { write() {}, close() {} },
                    postMessage() {}
                };
            }
            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
