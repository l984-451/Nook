// set-cookie.js / trusted-set-cookie.js — Sets a cookie to a specific value.
// Usage: set-cookie(name, value, [path])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const name = args[0] || '';
    const value = args[1] || '';
    const path = args[2] || '/';
    if (!name) return;

    // For consent cookies, common values
    let cookieValue = value;
    if (value === 'accept' || value === 'ok' || value === 'yes' || value === 'true' || value === '1') {
        cookieValue = value;
    } else if (value === 'reject' || value === 'no' || value === 'false' || value === '0') {
        cookieValue = value;
    }

    try {
        const maxAge = 365 * 24 * 60 * 60; // 1 year
        document.cookie = name + '=' + encodeURIComponent(cookieValue) + ';path=' + path + ';max-age=' + maxAge + ';SameSite=Lax';
    } catch (e) {}
})();
