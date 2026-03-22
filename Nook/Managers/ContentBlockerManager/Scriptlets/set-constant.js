// set-constant.js — Sets a property to a constant value.
// Usage: set-constant(propPath, value)
// value can be: true, false, 0, 1, '', undefined, null, noopFunc, trueFunc, falseFunc, ''
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const chain = (args[0] || '').split('.');
    const rawValue = args[1] || '';

    let value;
    switch (rawValue) {
        case 'true': value = true; break;
        case 'false': value = false; break;
        case '0': value = 0; break;
        case '1': value = 1; break;
        case "''": case '""': case '': value = ''; break;
        case 'undefined': value = undefined; break;
        case 'null': value = null; break;
        case 'noopFunc': value = function() {}; break;
        case 'trueFunc': value = function() { return true; }; break;
        case 'falseFunc': value = function() { return false; }; break;
        case '[]': value = []; break;
        case '{}': value = {}; break;
        default: value = rawValue; break;
    }

    let owner = window;
    for (let i = 0; i < chain.length - 1; i++) {
        if (!(chain[i] in owner)) {
            // Create intermediate objects so the trap works
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
            get() { return value; },
            set() {},
            configurable: false
        });
    } catch (e) {}
})();
