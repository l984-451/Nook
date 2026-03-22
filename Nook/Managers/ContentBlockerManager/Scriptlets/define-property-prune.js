// define-property-prune.js — Intercepts assignment to a window property and prunes specified keys.
// Usage: define-property-prune(propertyName, key1 key2 key3)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const propertyName = args[0] || '';
    const keysStr = args[1] || '';

    if (!propertyName || !keysStr) return;

    const keysToRemove = keysStr.split(/\s+/).filter(Boolean);

    function pruneObject(obj) {
        if (!obj || typeof obj !== 'object') return obj;
        for (const key of keysToRemove) {
            // Support dot-path keys like "args.raw_player_response.adPlacements"
            const parts = key.split('.');
            let target = obj;
            for (let i = 0; i < parts.length - 1; i++) {
                if (target && typeof target === 'object' && parts[i] in target) {
                    target = target[parts[i]];
                } else {
                    target = null;
                    break;
                }
            }
            if (target && typeof target === 'object') {
                delete target[parts[parts.length - 1]];
            }
        }
        return obj;
    }

    let storedValue = window[propertyName];
    if (storedValue && typeof storedValue === 'object') {
        storedValue = pruneObject(storedValue);
    }

    Object.defineProperty(window, propertyName, {
        configurable: true,
        enumerable: true,
        get() {
            return storedValue;
        },
        set(newValue) {
            if (newValue && typeof newValue === 'object') {
                storedValue = pruneObject(newValue);
            } else {
                storedValue = newValue;
            }
        }
    });
})();
