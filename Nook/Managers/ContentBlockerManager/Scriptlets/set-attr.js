// set-attr.js — Sets an attribute on matching elements.
// Usage: set-attr(selector, attr, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const selector = args[0] || '';
    const attr = args[1] || '';
    const value = args[2] || '';
    if (!selector || !attr) return;

    function setAttrs() {
        try {
            const elems = document.querySelectorAll(selector);
            for (const el of elems) {
                el.setAttribute(attr, value);
            }
        } catch (e) {}
    }

    setAttrs();
    const observer = new MutationObserver(setAttrs);
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            setAttrs();
            observer.observe(document.body, { childList: true, subtree: true, attributes: true });
        });
    } else {
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true, attributes: true });
    }
})();
