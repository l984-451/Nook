// close-window.js — Close window if URL matches pattern.
// Usage: close-window([urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const urlPattern = args[0] || '';

    if (urlPattern) {
        let urlRe;
        try { urlRe = new RegExp(urlPattern); } catch (e) {
            urlRe = { test: (s) => s.includes(urlPattern) };
        }
        if (!urlRe.test(window.location.href)) return;
    }

    window.close();
})();
