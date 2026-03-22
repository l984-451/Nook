// removeparam-engine.js — Strips matching query parameters from URLs.
// Intercepts history.pushState/replaceState and MutationObserver on <a> hrefs.
// Usage: removeparam-engine(paramPatterns) — paramPatterns is JSON array of patterns
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const paramPatterns = args[0] || '';
    if (!paramPatterns) return;

    let patterns;
    try {
        patterns = JSON.parse(paramPatterns);
    } catch(e) {
        patterns = paramPatterns.split(/\s+/);
    }

    const regexPatterns = patterns.map(p => {
        if (p === '*') return { test: () => true };
        try { return new RegExp(p); } catch(e) { return { test: (s) => s === p }; }
    });

    function shouldRemoveParam(name) {
        return regexPatterns.some(re => re.test(name));
    }

    function cleanURL(urlStr) {
        try {
            const url = new URL(urlStr, location.href);
            const params = new URLSearchParams(url.search);
            let modified = false;
            const toDelete = [];
            for (const [key] of params) {
                if (shouldRemoveParam(key)) {
                    toDelete.push(key);
                    modified = true;
                }
            }
            for (const key of toDelete) {
                params.delete(key);
            }
            if (modified) {
                url.search = params.toString();
                return url.href;
            }
        } catch(e) {}
        return null;
    }

    // Intercept pushState/replaceState
    const origPushState = history.pushState;
    const origReplaceState = history.replaceState;

    history.pushState = function(state, title, url) {
        if (url) {
            const cleaned = cleanURL(String(url));
            if (cleaned) url = cleaned;
        }
        return origPushState.call(this, state, title, url);
    };

    history.replaceState = function(state, title, url) {
        if (url) {
            const cleaned = cleanURL(String(url));
            if (cleaned) url = cleaned;
        }
        return origReplaceState.call(this, state, title, url);
    };

    // Clean <a> href attributes
    function cleanLinks() {
        const links = document.querySelectorAll('a[href]');
        for (const link of links) {
            if (link.dataset.nookCleaned) continue;
            const href = link.getAttribute('href');
            if (!href || !href.includes('?')) continue;
            const cleaned = cleanURL(href);
            if (cleaned) {
                link.setAttribute('href', cleaned);
                link.dataset.nookCleaned = '1';
            }
        }
    }

    // Observe DOM for new links
    const observer = new MutationObserver(cleanLinks);
    if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            observer.observe(document.body, { childList: true, subtree: true });
        });
    }

    // Initial clean
    if (document.readyState !== 'loading') {
        cleanLinks();
    } else {
        document.addEventListener('DOMContentLoaded', cleanLinks);
    }
})();
