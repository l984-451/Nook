// trusted-prune-inbound-object.js — Prune keys from function arguments.
// Usage: trusted-prune-inbound-object(funcPath, keys)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const funcPath = args[0] || '';
    const keys = (args[1] || '').split(/\s+/);
    if (!funcPath || keys.length === 0) return;

    const pruneKeys = keys.map(k => k.split('.'));

    function pruneObject(obj) {
        if (typeof obj !== 'object' || obj === null) return;
        for (const keyPath of pruneKeys) {
            let current = obj;
            for (let i = 0; i < keyPath.length - 1; i++) {
                if (current == null || typeof current !== 'object') break;
                current = current[keyPath[i]];
            }
            if (current != null && typeof current === 'object') {
                delete current[keyPath[keyPath.length - 1]];
            }
        }
    }

    const parts = funcPath.split('.');
    let target = window;
    for (let i = 0; i < parts.length - 1; i++) { if (target == null) return; target = target[parts[i]]; }
    const methodName = parts[parts.length - 1];
    if (!target || typeof target[methodName] !== 'function') return;

    const original = target[methodName];
    target[methodName] = function() {
        for (let i = 0; i < arguments.length; i++) {
            if (typeof arguments[i] === 'object' && arguments[i] !== null) pruneObject(arguments[i]);
        }
        return original.apply(this, arguments);
    };
})();
