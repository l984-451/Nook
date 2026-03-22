// nano-stb.js — Speeds up setTimeout-based countdown timers (anti-adblock bypasses).
// Usage: nano-stb([needle], [delay])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const needle = args[0] || '';
    const boost = parseInt(args[1]) || 0.02;

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
            let delay = argumentsList[1];

            if (typeof callback === 'function' && typeof delay === 'number' && delay >= 50) {
                const callbackStr = String(callback);
                if (!needle || (needleRe && needleRe.test(callbackStr))) {
                    argumentsList[1] = Math.max(delay * boost, 1);
                }
            }

            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
