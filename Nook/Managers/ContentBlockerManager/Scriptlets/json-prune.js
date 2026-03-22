// json-prune.js — Wraps JSON.parse() to remove specified keys from parsed objects.
// Critical for YouTube: prunes playerAds, adPlacements, adSlots from player responses.
// Usage: json-prune(key1 key2, [optional propsToMatch])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const rawKeys = (args[0] || '').split(/\s+/);
    const propsToMatch = args[1] || '';

    const originalParse = JSON.parse;

    const pruneKeys = rawKeys.map(k => {
        const parts = k.split('.');
        return parts;
    });

    function shouldPrune(obj) {
        if (!propsToMatch) return true;
        const checks = propsToMatch.split(/\s+/);
        for (const check of checks) {
            const [path, val] = check.split(':');
            let current = obj;
            for (const part of path.split('.')) {
                if (current == null || typeof current !== 'object') return false;
                if (!(part in current)) return false;
                current = current[part];
            }
            if (val !== undefined && String(current) !== val) return false;
        }
        return true;
    }

    function pruneObject(obj) {
        if (typeof obj !== 'object' || obj === null) return obj;
        if (!shouldPrune(obj)) return obj;

        for (const keyPath of pruneKeys) {
            let current = obj;
            for (let i = 0; i < keyPath.length - 1; i++) {
                if (current == null || typeof current !== 'object') break;
                current = current[keyPath[i]];
            }
            if (current != null && typeof current === 'object') {
                const lastKey = keyPath[keyPath.length - 1];
                if (lastKey in current) {
                    delete current[lastKey];
                }
            }
        }
        return obj;
    }

    JSON.parse = new Proxy(originalParse, {
        apply(target, thisArg, argumentsList) {
            const result = Reflect.apply(target, thisArg, argumentsList);
            try {
                return pruneObject(result);
            } catch (e) {
                return result;
            }
        }
    });
})();
