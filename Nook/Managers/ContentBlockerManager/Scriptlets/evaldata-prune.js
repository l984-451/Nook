// evaldata-prune.js — Intercept eval(), prune JSON-like data within.
// Usage: evaldata-prune(keys, [propsToMatch])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const rawKeys = (args[0] || '').split(/\s+/);
    const propsToMatch = args[1] || '';

    const pruneKeys = rawKeys.map(k => k.split('.'));

    function pruneObject(obj) {
        if (typeof obj !== 'object' || obj === null) return obj;
        for (const keyPath of pruneKeys) {
            let current = obj;
            for (let i = 0; i < keyPath.length - 1; i++) {
                if (current == null || typeof current !== 'object') break;
                current = current[keyPath[i]];
            }
            if (current != null && typeof current === 'object') {
                const lastKey = keyPath[keyPath.length - 1];
                if (lastKey in current) delete current[lastKey];
            }
        }
        return obj;
    }

    const originalEval = window.eval;
    window.eval = function(code) {
        if (typeof code === 'string') {
            // Try to find and prune JSON-like structures
            try {
                const jsonMatch = code.match(/(\{[\s\S]*\})/);
                if (jsonMatch) {
                    const json = JSON.parse(jsonMatch[1]);
                    if (!propsToMatch || Object.keys(json).some(k => k.includes(propsToMatch))) {
                        const pruned = pruneObject(json);
                        code = code.replace(jsonMatch[1], JSON.stringify(pruned));
                    }
                }
            } catch (e) {}
        }
        return originalEval.call(this, code);
    };
})();
