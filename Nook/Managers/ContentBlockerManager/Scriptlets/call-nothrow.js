// call-nothrow.js — Wrap function at path in try/catch so it never throws.
// Usage: call-nothrow(functionPath)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const functionPath = args[0] || '';
    if (!functionPath) return;

    const parts = functionPath.split('.');
    let target = window;
    for (let i = 0; i < parts.length - 1; i++) {
        if (target == null) return;
        target = target[parts[i]];
    }
    const methodName = parts[parts.length - 1];
    if (!target || typeof target[methodName] !== 'function') return;

    const original = target[methodName];
    target[methodName] = function() {
        try {
            return original.apply(this, arguments);
        } catch (e) {
            return undefined;
        }
    };
})();
