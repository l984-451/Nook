// abort-on-property-write.js — Throws on property set to prevent ad code setup.
// Usage: abort-on-property-write(propPath)
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
    const existing = owner[prop];
    try {
        Object.defineProperty(owner, prop, {
            get() { return existing; },
            set() {
                throw new ReferenceError('Nook: property write aborted: ' + args[0]);
            },
            configurable: false
        });
    } catch (e) {}
})();
