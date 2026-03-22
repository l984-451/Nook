// trusted-set-cookie.js — Set cookies with any value (trusted version, unrestricted).
// Usage: trusted-set-cookie(name, value, [path], [expires])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const name = args[0] || '';
    const value = args[1] || '';
    const path = args[2] || '/';
    const expires = args[3] || '';
    if (!name) return;

    let cookieStr = name + '=' + encodeURIComponent(value) + ';path=' + path + ';SameSite=Lax';
    if (expires) {
        if (expires === 'session') {
            // No max-age for session cookies
        } else {
            const days = parseInt(expires, 10);
            if (!isNaN(days)) {
                cookieStr += ';max-age=' + (days * 24 * 60 * 60);
            } else {
                cookieStr += ';expires=' + expires;
            }
        }
    } else {
        cookieStr += ';max-age=' + (365 * 24 * 60 * 60);
    }

    try { document.cookie = cookieStr; } catch(e) {}
})();
