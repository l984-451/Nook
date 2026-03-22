// trusted-replace-argument.js — Replaces arguments of a specific function call.
// Usage: trusted-replace-argument(propPath, argIndex, replacement)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const prop = args[0] || '';
    const argIndex = parseInt(args[1]) || 0;
    const replacement = args[2] || '';
    if (!prop) return;

    const chain = prop.split('.');
    let owner = window;
    for (let i = 0; i < chain.length - 1; i++) {
        if (!(chain[i] in owner)) return;
        owner = owner[chain[i]];
        if (owner == null) return;
    }

    const target = chain[chain.length - 1];
    const original = owner[target];
    if (typeof original !== 'function') return;

    owner[target] = new Proxy(original, {
        apply(t, thisArg, argumentsList) {
            if (argumentsList.length > argIndex) {
                argumentsList[argIndex] = replacement;
            }
            return Reflect.apply(t, thisArg, argumentsList);
        }
    });
})();
