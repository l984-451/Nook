// edit-inbound-object.js — Non-trusted version: edit function arguments (restricted value types).
// Usage: edit-inbound-object(funcPath, propPath, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const funcPath = args[0] || '';
    const propPath = args[1] || '';
    const value = args[2];
    if (!funcPath || !propPath) return;

    function parseValue(val) {
        if (val === undefined || val === '') return '';
        if (val === 'true') return true;
        if (val === 'false') return false;
        if (val === 'null') return null;
        if (val === '0') return 0;
        if (val === '1') return 1;
        const num = Number(val);
        if (!isNaN(num) && val !== '') return num;
        return val;
    }

    function setNestedProp(obj, path, val) {
        const parts = path.split('.');
        let current = obj;
        for (let i = 0; i < parts.length - 1; i++) {
            if (current == null || typeof current !== 'object') return;
            if (!(parts[i] in current)) return;
            current = current[parts[i]];
        }
        if (current != null && typeof current === 'object') {
            current[parts[parts.length - 1]] = parseValue(val);
        }
    }

    const parts = funcPath.split('.');
    let target = window;
    for (let i = 0; i < parts.length - 1; i++) { if (target == null) return; target = target[parts[i]]; }
    const methodName = parts[parts.length - 1];
    if (!target || typeof target[methodName] !== 'function') return;

    const original = target[methodName];
    target[methodName] = function() {
        const modifiedArgs = Array.from(arguments);
        for (let i = 0; i < modifiedArgs.length; i++) {
            if (typeof modifiedArgs[i] === 'object' && modifiedArgs[i] !== null) setNestedProp(modifiedArgs[i], propPath, value);
        }
        return original.apply(this, modifiedArgs);
    };
})();
