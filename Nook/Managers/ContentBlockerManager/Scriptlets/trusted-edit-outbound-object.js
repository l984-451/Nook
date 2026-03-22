// trusted-edit-outbound-object.js — Edit function return values.
// Usage: trusted-edit-outbound-object(funcPath, propPath, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const funcPath = args[0] || '';
    const propPath = args[1] || '';
    const value = args[2];
    if (!funcPath || !propPath) return;

    function parseValue(val) {
        if (val === undefined || val === '') return undefined;
        if (val === 'true') return true;
        if (val === 'false') return false;
        if (val === 'null') return null;
        if (val === 'undefined') return undefined;
        if (val === '""' || val === "''") return '';
        const num = Number(val);
        if (!isNaN(num) && val !== '') return num;
        try { return JSON.parse(val); } catch (e) {}
        return val;
    }

    function setNestedProp(obj, path, val) {
        const parts = path.split('.');
        let current = obj;
        for (let i = 0; i < parts.length - 1; i++) {
            if (current == null || typeof current !== 'object') return;
            if (!(parts[i] in current)) current[parts[i]] = {};
            current = current[parts[i]];
        }
        if (current != null && typeof current === 'object') {
            current[parts[parts.length - 1]] = parseValue(val);
        }
    }

    const parts = funcPath.split('.');
    let target = window;
    for (let i = 0; i < parts.length - 1; i++) {
        if (target == null) return;
        target = target[parts[i]];
    }
    const methodName = parts[parts.length - 1];
    if (!target || typeof target[methodName] !== 'function') return;

    const original = target[methodName];
    target[methodName] = function() {
        const result = original.apply(this, arguments);
        if (typeof result === 'object' && result !== null) {
            setNestedProp(result, propPath, value);
        }
        return result;
    };
})();
