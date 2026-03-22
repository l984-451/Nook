// disable-newtab-links.js — Forces links that open in new tabs to open in same tab.
// Usage: disable-newtab-links()
(function() {
    'use strict';

    function fixLinks() {
        const links = document.querySelectorAll('a[target="_blank"]');
        for (const link of links) {
            link.removeAttribute('target');
            link.removeAttribute('rel');
        }
    }

    fixLinks();
    const observer = new MutationObserver(fixLinks);
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            fixLinks();
            observer.observe(document.body, { childList: true, subtree: true });
        });
    } else {
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
    }
})();
