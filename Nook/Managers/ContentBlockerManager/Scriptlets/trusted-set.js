// trusted-set.js — Like set-constant but with no restrictions on values.
// Usage: trusted-set(propPath, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const chain = (args[0] || '').split('.');
    const rawValue = args[1] || '';

    let value;
    switch (rawValue) {
        case 'true': value = true; break;
        case 'false': value = false; break;
        case 'null': value = null; break;
        case 'undefined': value = undefined; break;
        case 'noopFunc': value = function() {}; break;
        case 'trueFunc': value = function() { return true; }; break;
        case 'falseFunc': value = function() { return false; }; break;
        case '[]': value = []; break;
        case '{}': value = {}; break;
        default:
            if (/^\d+$/.test(rawValue)) value = parseInt(rawValue);
            else if (/^\d+\.\d+$/.test(rawValue)) value = parseFloat(rawValue);
            else value = rawValue;
            break;
    }

    let owner = window;
    for (let i = 0; i < chain.length - 1; i++) {
        if (!(chain[i] in owner)) {
            const next = {};
            try {
                Object.defineProperty(owner, chain[i], { get() { return next; }, set() {}, configurable: true });
            } catch (e) { owner[chain[i]] = next; }
            owner = next;
            continue;
        }
        owner = owner[chain[i]];
        if (owner == null) return;
    }

    const prop = chain[chain.length - 1];
    try {
        Object.defineProperty(owner, prop, { get() { return value; }, set() {}, configurable: true });
    } catch (e) {
        try { owner[prop] = value; } catch (e2) {}
    }
})();
