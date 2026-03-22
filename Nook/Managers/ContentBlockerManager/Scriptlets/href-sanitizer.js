// href-sanitizer.js — Removes tracking redirects from link hrefs.
// Usage: href-sanitizer(selector, [attrOrProp])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const selector = args[0] || 'a[href]';
    const attr = args[1] || 'text';

    function sanitize() {
        try {
            const links = document.querySelectorAll(selector);
            for (const link of links) {
                const href = link.getAttribute('href');
                if (!href) continue;
                let clean = '';
                if (attr === 'text') {
                    const text = link.textContent.trim();
                    if (/^https?:\/\//.test(text)) clean = text;
                } else if (attr.startsWith('?')) {
                    try {
                        const url = new URL(href, location.href);
                        clean = url.searchParams.get(attr.slice(1)) || '';
                    } catch (e) {}
                } else if (attr.startsWith('[')) {
                    const a = attr.slice(1, -1);
                    clean = link.getAttribute(a) || '';
                }
                if (clean && /^https?:\/\//.test(clean)) {
                    link.setAttribute('href', clean);
                }
            }
        } catch (e) {}
    }

    const observer = new MutationObserver(sanitize);
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            sanitize();
            observer.observe(document.body, { childList: true, subtree: true });
        });
    } else {
        sanitize();
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
    }
})();
