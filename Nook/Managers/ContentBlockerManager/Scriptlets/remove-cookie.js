// remove-cookie.js (cookie-remover) — Removes cookies matching a pattern.
// Usage: remove-cookie(name)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const needle = args[0] || '';

    let needleRe;
    if (needle) {
        try { needleRe = new RegExp(needle); } catch (e) {
            needleRe = { test: (s) => s.includes(needle) };
        }
    }

    function removeCookies() {
        try {
            const cookies = document.cookie.split(';');
            for (const cookie of cookies) {
                const name = cookie.split('=')[0].trim();
                if (!needle || (needleRe && needleRe.test(name))) {
                    const paths = ['/', window.location.pathname];
                    const domains = [window.location.hostname, '.' + window.location.hostname];
                    for (const path of paths) {
                        for (const domain of domains) {
                            document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=' + path + ';domain=' + domain;
                        }
                        document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=' + path;
                    }
                }
            }
        } catch (e) {}
    }

    removeCookies();
    window.addEventListener('beforeunload', removeCookies);
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', removeCookies);
    }
})();
