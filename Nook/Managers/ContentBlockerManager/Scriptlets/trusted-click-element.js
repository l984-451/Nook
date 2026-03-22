// trusted-click-element.js — MutationObserver + click matching elements.
// Usage: trusted-click-element(selector, [delay])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const selector = args[0] || '';
    const delay = parseInt(args[1], 10) || 0;
    if (!selector) return;

    function clickMatching() {
        const elements = document.querySelectorAll(selector);
        for (const el of elements) {
            if (delay > 0) {
                setTimeout(() => el.click(), delay);
            } else {
                el.click();
            }
        }
    }

    const observer = new MutationObserver(clickMatching);
    if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            observer.observe(document.body, { childList: true, subtree: true });
        });
    }
    // Initial check
    if (document.readyState !== 'loading') {
        clickMatching();
    } else {
        document.addEventListener('DOMContentLoaded', clickMatching);
    }
})();
