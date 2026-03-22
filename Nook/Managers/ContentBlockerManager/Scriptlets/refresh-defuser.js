// refresh-defuser.js — Prevents meta refresh and location-based redirects.
// Usage: refresh-defuser([delay])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');

    // Block meta refresh
    const observer = new MutationObserver(function() {
        const metas = document.querySelectorAll('meta[http-equiv="refresh"]');
        for (const meta of metas) {
            meta.remove();
        }
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });

    // Block location.assign/replace redirects (optional, aggressive)
    if (args[0]) {
        const origAssign = location.assign;
        const origReplace = location.replace;
        location.assign = function() {};
        location.replace = function() {};
    }
})();
