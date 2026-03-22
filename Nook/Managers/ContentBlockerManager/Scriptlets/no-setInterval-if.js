// no-setInterval-if.js (nosiif) — Prevents setInterval calls matching a pattern.
// Usage: no-setInterval-if([needle], [delay])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const needle = args[0] || '';
    const delay = args[1] || '';

    let needleRe;
    if (needle) {
        try { needleRe = new RegExp(needle); } catch (e) {
            needleRe = { test: (s) => s.includes(needle) };
        }
    }

    const origSetInterval = window.setInterval;
    window.setInterval = new Proxy(origSetInterval, {
        apply(target, thisArg, argumentsList) {
            const callback = argumentsList[0];
            const ms = argumentsList[1];
            const callbackStr = typeof callback === 'function' ? callback.toString() : String(callback);

            if (needleRe && needleRe.test(callbackStr)) {
                if (delay && String(ms) !== delay) {
                    return Reflect.apply(target, thisArg, argumentsList);
                }
                return 0; // Block
            }
            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
