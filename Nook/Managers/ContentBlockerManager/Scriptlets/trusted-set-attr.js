// trusted-set-attr.js — Set arbitrary attribute values on elements.
// Usage: trusted-set-attr(selector, attr, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const selector = args[0] || '';
    const attr = args[1] || '';
    const value = args[2] || '';
    if (!selector || !attr) return;

    function apply() {
        const elements = document.querySelectorAll(selector);
        for (const el of elements) {
            el.setAttribute(attr, value);
        }
    }

    const observer = new MutationObserver(apply);
    if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            observer.observe(document.body, { childList: true, subtree: true });
        });
    }
    if (document.readyState !== 'loading') apply();
    else document.addEventListener('DOMContentLoaded', apply);
})();
