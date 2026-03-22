// set-local-storage-item.js — Sets a localStorage key to a specific value.
// Usage: set-local-storage-item(key, value)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const key = args[0] || '';
    const value = args[1] || '';
    if (!key) return;
    try {
        localStorage.setItem(key, value);
    } catch (e) {}
})();
