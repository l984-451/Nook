// no-setTimeout-if.js (nostif) — Prevents setTimeout calls matching a pattern.
// Usage: no-setTimeout-if([needle], [delay])
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

    const origSetTimeout = window.setTimeout;
    window.setTimeout = new Proxy(origSetTimeout, {
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
