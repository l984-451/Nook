// abort-on-stack-trace.js (aost) — Aborts when property access has matching stack trace.
// Usage: abort-on-stack-trace(property, stackNeedle)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const prop = args[0] || '';
    const needle = args[1] || '';
    if (!prop) return;

    let needleRe;
    if (needle) {
        try { needleRe = new RegExp(needle); } catch (e) {
            needleRe = { test: (s) => s.includes(needle) };
        }
    }

    const chain = prop.split('.');
    let owner = window;
    for (let i = 0; i < chain.length - 1; i++) {
        if (!(chain[i] in owner)) return;
        owner = owner[chain[i]];
        if (owner == null) return;
    }

    const target = chain[chain.length - 1];
    const original = owner[target];

    if (typeof original === 'function') {
        owner[target] = new Proxy(original, {
            apply(t, thisArg, argumentsList) {
                if (needleRe) {
                    const stack = new Error().stack || '';
                    if (needleRe.test(stack)) {
                        throw new ReferenceError('Nook: abort-on-stack-trace');
                    }
                }
                return Reflect.apply(t, thisArg, argumentsList);
            }
        });
    }
})();
