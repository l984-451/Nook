// remove-cache-storage-item.js — Delete named caches via caches.delete().
// Usage: remove-cache-storage-item(cacheName)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const cacheName = args[0] || '';
    if (!cacheName) return;

    let cacheRe;
    try { cacheRe = new RegExp(cacheName); } catch (e) {
        cacheRe = { test: (s) => s.includes(cacheName) };
    }

    if (typeof caches !== 'undefined' && caches.keys) {
        caches.keys().then(names => {
            for (const name of names) {
                if (cacheRe.test(name)) {
                    caches.delete(name);
                }
            }
        }).catch(() => {});
    }
})();
