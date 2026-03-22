// set-cookie-reload.js — Set cookie then reload the page.
// Usage: set-cookie-reload(name, value, [path])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const name = args[0] || '';
    const value = args[1] || '';
    const path = args[2] || '/';
    if (!name) return;

    // Check if cookie already set to avoid reload loops
    const cookies = document.cookie.split(';');
    for (const cookie of cookies) {
        const [cName, cValue] = cookie.trim().split('=');
        if (cName === name && cValue === encodeURIComponent(value)) return;
    }

    const maxAge = 365 * 24 * 60 * 60;
    document.cookie = name + '=' + encodeURIComponent(value) + ';path=' + path + ';max-age=' + maxAge + ';SameSite=Lax';
    window.location.reload();
})();
