// noeval-if.js — Blocks eval() calls matching a pattern.
// Usage: noeval-if([needle])
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

    const origEval = window.eval;
    window.eval = new Proxy(origEval, {
        apply(target, thisArg, argumentsList) {
            const code = String(argumentsList[0] || '');
            if (!needle || (needleRe && needleRe.test(code))) {
                return; // Block
            }
            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
