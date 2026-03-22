// abort-on-property-read.js — Throws ReferenceError on property access to prevent ad code init.
// Usage: abort-on-property-read(propPath)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const chain = (args[0] || '').split('.');

    let owner = window;
    for (let i = 0; i < chain.length - 1; i++) {
        if (!(chain[i] in owner)) {
            const next = {};
            Object.defineProperty(owner, chain[i], {
                get() { return next; },
                set() {},
                configurable: true
            });
            owner = next;
            continue;
        }
        owner = owner[chain[i]];
        if (owner == null) return;
    }

    const prop = chain[chain.length - 1];
    try {
        Object.defineProperty(owner, prop, {
            get() {
                throw new ReferenceError('Nook: property read aborted: ' + args[0]);
            },
            set() {},
            configurable: false
        });
    } catch (e) {}
})();
