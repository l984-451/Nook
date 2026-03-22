// trusted-set-local-storage-item.js — Set localStorage with arbitrary values (trusted).
// Usage: trusted-set-local-storage-item(key, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const key = args[0] || '';
    const value = args[1] || '';
    if (!key) return;
    try { localStorage.setItem(key, value); } catch(e) {}
})();
