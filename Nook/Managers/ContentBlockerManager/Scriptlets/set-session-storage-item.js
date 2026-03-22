// set-session-storage-item.js — Sets a sessionStorage key to a specific value.
// Usage: set-session-storage-item(key, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const key = args[0] || '';
    const value = args[1] || '';
    if (!key) return;
    try {
        sessionStorage.setItem(key, value);
    } catch (e) {}
})();
