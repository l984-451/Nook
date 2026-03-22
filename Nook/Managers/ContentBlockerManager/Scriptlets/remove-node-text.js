// remove-node-text.js (rmnt) — Removes text nodes matching a pattern from specific elements.
// Usage: remove-node-text(nodeName, textPattern)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const nodeName = (args[0] || '').toLowerCase();
    const needle = args[1] || '';
    if (!nodeName || !needle) return;

    let needleRe;
    try { needleRe = new RegExp(needle); } catch (e) {
        needleRe = { test: (s) => s.includes(needle) };
    }

    function removeText() {
        const elements = document.querySelectorAll(nodeName);
        for (const el of elements) {
            if (needleRe.test(el.textContent)) {
                el.textContent = '';
            }
        }
    }

    const observer = new MutationObserver(removeText);
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            removeText();
            observer.observe(document.body, { childList: true, subtree: true });
        });
    } else {
        removeText();
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
    }
})();
