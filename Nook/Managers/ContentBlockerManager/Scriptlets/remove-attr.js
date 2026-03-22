// remove-attr.js — Removes specified attributes from matching elements.
// Usage: remove-attr(attrName, [selector], [applying])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const attrNames = (args[0] || '').split(/\|/);
    const selector = args[1] || '[' + attrNames[0] + ']';
    const applying = args[2] || 'asap stay';

    function removeAttrs() {
        try {
            const elems = document.querySelectorAll(selector);
            for (const el of elems) {
                for (const attr of attrNames) {
                    el.removeAttribute(attr);
                }
            }
        } catch (e) {}
    }

    if (applying.includes('asap')) {
        removeAttrs();
    }
    if (applying.includes('stay')) {
        const observer = new MutationObserver(removeAttrs);
        observer.observe(document, { subtree: true, childList: true, attributes: true });
    }
    if (applying.includes('complete')) {
        if (document.readyState === 'complete') {
            removeAttrs();
        } else {
            window.addEventListener('load', removeAttrs, { once: true });
        }
    }
})();
