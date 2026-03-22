// prevent-navigation.js — Override location.assign/replace/href setter, block matching URLs.
// Usage: prevent-navigation(urlPattern)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const urlPattern = args[0] || '';
    if (!urlPattern) return;

    let urlRe;
    try { urlRe = new RegExp(urlPattern); } catch (e) {
        urlRe = { test: (s) => s.includes(urlPattern) };
    }

    // Override location.assign
    const origAssign = window.location.assign;
    if (origAssign) {
        window.location.assign = function(url) {
            if (urlRe.test(String(url))) return;
            return origAssign.call(this, url);
        };
    }

    // Override location.replace
    const origReplace = window.location.replace;
    if (origReplace) {
        window.location.replace = function(url) {
            if (urlRe.test(String(url))) return;
            return origReplace.call(this, url);
        };
    }

    // Override window.open
    const origOpen = window.open;
    window.open = function(url) {
        if (url && urlRe.test(String(url))) return null;
        return origOpen.apply(this, arguments);
    };
})();
