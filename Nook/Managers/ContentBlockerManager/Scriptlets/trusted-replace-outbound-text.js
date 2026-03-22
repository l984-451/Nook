// trusted-replace-outbound-text.js — Replace text in function return strings.
// Usage: trusted-replace-outbound-text(funcPath, pattern, replacement)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const funcPath = args[0] || '';
    const pattern = args[1] || '';
    const replacement = args[2] || '';
    if (!funcPath || !pattern) return;

    let patternRe;
    try { patternRe = new RegExp(pattern, 'g'); } catch(e) { patternRe = null; }

    const parts = funcPath.split('.');
    let target = window;
    for (let i = 0; i < parts.length - 1; i++) { if (target == null) return; target = target[parts[i]]; }
    const methodName = parts[parts.length - 1];
    if (!target || typeof target[methodName] !== 'function') return;

    const original = target[methodName];
    target[methodName] = function() {
        const result = original.apply(this, arguments);
        if (typeof result === 'string') {
            if (patternRe) return result.replace(patternRe, replacement);
            return result.split(pattern).join(replacement);
        }
        return result;
    };
})();
