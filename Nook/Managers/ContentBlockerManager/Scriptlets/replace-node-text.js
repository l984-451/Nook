// replace-node-text.js (rpnt/trusted-rpnt) — Replaces text in specific elements.
// Usage: replace-node-text(nodeName, pattern, replacement)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const nodeName = (args[0] || '').toLowerCase();
    const pattern = args[1] || '';
    const replacement = args[2] || '';
    if (!nodeName || !pattern) return;

    let patternRe;
    try { patternRe = new RegExp(pattern, 'g'); } catch (e) {
        patternRe = null;
    }

    function replaceText() {
        const elements = document.querySelectorAll(nodeName);
        for (const el of elements) {
            const text = el.textContent;
            let modified;
            if (patternRe) {
                modified = text.replace(patternRe, replacement);
            } else {
                modified = text.split(pattern).join(replacement);
            }
            if (modified !== text) {
                el.textContent = modified;
            }
        }
    }

    const observer = new MutationObserver(replaceText);
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            replaceText();
            observer.observe(document.body, { childList: true, subtree: true });
        });
    } else {
        replaceText();
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
    }
})();
