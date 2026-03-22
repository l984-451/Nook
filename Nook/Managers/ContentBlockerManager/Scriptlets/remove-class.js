// remove-class.js — Removes specified CSS classes from matching elements.
// Usage: remove-class(className, [selector], [applying])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const classNames = (args[0] || '').split(/\|/);
    const selector = args[1] || '.' + classNames[0];
    const applying = args[2] || 'asap stay';

    function removeClasses() {
        try {
            const elems = document.querySelectorAll(selector);
            for (const el of elems) {
                for (const cls of classNames) {
                    el.classList.remove(cls);
                }
            }
        } catch (e) {}
    }

    if (applying.includes('asap')) {
        removeClasses();
    }
    if (applying.includes('stay')) {
        const observer = new MutationObserver(removeClasses);
        observer.observe(document, { subtree: true, childList: true, attributes: true });
    }
    if (applying.includes('complete')) {
        if (document.readyState === 'complete') {
            removeClasses();
        } else {
            window.addEventListener('load', removeClasses, { once: true });
        }
    }
})();
