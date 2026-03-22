// trusted-suppress-native-method.js — Replace a native method with a no-op or conditional wrapper.
// Navigate dot-path to method, replace with function that checks args against pattern.
// Usage: trusted-suppress-native-method(methodPath, [argsPattern], [returnValue])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const methodPath = args[0] || '';
    const argsPattern = args[1] || '';
    const returnValue = args[2];

    if (!methodPath) return;

    let argsRe;
    if (argsPattern) {
        try { argsRe = new RegExp(argsPattern); } catch (e) {
            argsRe = { test: (s) => s.includes(argsPattern) };
        }
    }

    function parseReturnValue(val) {
        if (val === undefined || val === '') return undefined;
        if (val === 'undefined') return undefined;
        if (val === 'null') return null;
        if (val === 'true') return true;
        if (val === 'false') return false;
        if (val === 'noopFunc') return function() {};
        if (val === 'trueFunc') return function() { return true; };
        if (val === 'falseFunc') return function() { return false; };
        if (val === '""' || val === "''") return '';
        if (val === '[]') return [];
        if (val === '{}') return {};
        if (val === '0') return 0;
        if (val === '1') return 1;
        if (val === '-1') return -1;
        if (val === 'NaN') return NaN;
        if (val === 'Infinity') return Infinity;
        const num = Number(val);
        if (!isNaN(num)) return num;
        return val;
    }

    const parts = methodPath.split('.');
    let target = window;
    for (let i = 0; i < parts.length - 1; i++) {
        if (target == null) return;
        target = target[parts[i]];
    }

    const methodName = parts[parts.length - 1];
    if (!target || typeof target[methodName] !== 'function') return;

    const original = target[methodName];
    const retVal = parseReturnValue(returnValue);

    target[methodName] = function() {
        if (argsRe) {
            // Check if any argument matches the pattern
            const argsStr = Array.from(arguments).map(a => {
                try { return String(a); } catch (e) { return ''; }
            }).join(' ');
            if (argsRe.test(argsStr)) {
                return retVal;
            }
            return original.apply(this, arguments);
        }
        // No pattern — always suppress
        return retVal;
    };

    // Preserve function properties
    try {
        Object.defineProperty(target[methodName], 'name', { value: original.name });
        Object.defineProperty(target[methodName], 'length', { value: original.length });
    } catch (e) {}
})();
