// trusted-set-session-storage-item.js — Set sessionStorage with arbitrary values (trusted).
// Usage: trusted-set-session-storage-item(key, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const key = args[0] || '';
    const value = args[1] || '';
    if (!key) return;
    try { sessionStorage.setItem(key, value); } catch(e) {}
})();
