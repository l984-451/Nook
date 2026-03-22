// no-beacon-if.js — Wraps Navigator.sendBeacon() to block calls matching a URL pattern.
// Usage: no-beacon-if(urlPattern)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const urlPattern = args[0] || '';

    let urlRe;
    try { urlRe = new RegExp(urlPattern); } catch (e) {
        urlRe = { test: (s) => s.includes(urlPattern) };
    }

    const origBeacon = Navigator.prototype.sendBeacon;
    if (typeof origBeacon !== 'function') return;

    Navigator.prototype.sendBeacon = function(url) {
        const urlStr = String(url);
        if (urlRe.test(urlStr)) {
            return true; // Pretend success
        }
        return origBeacon.apply(this, arguments);
    };
})();
