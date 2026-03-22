// no-requestAnimationFrame-if.js (norafif) — Blocks requestAnimationFrame matching a pattern.
// Usage: no-requestAnimationFrame-if([needle])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const needle = args[0] || '';

    let needleRe;
    if (needle) {
        try { needleRe = new RegExp(needle); } catch (e) {
            needleRe = { test: (s) => s.includes(needle) };
        }
    }

    const origRAF = window.requestAnimationFrame;
    window.requestAnimationFrame = new Proxy(origRAF, {
        apply(target, thisArg, argumentsList) {
            const cb = argumentsList[0];
            if (needleRe && typeof cb === 'function') {
                if (needleRe.test(cb.toString())) {
                    return 0;
                }
            }
            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
