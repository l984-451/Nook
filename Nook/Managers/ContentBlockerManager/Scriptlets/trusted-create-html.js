// trusted-create-html.js — Insert HTML into DOM.
// Usage: trusted-create-html(parentSelector, position, html)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const parentSelector = args[0] || '';
    const position = args[1] || 'beforeend';
    const html = args[2] || '';
    if (!parentSelector || !html) return;

    function inject() {
        const parent = document.querySelector(parentSelector);
        if (parent) {
            parent.insertAdjacentHTML(position, html);
        }
    }

    if (document.readyState !== 'loading') {
        inject();
    } else {
        document.addEventListener('DOMContentLoaded', inject);
    }
})();
