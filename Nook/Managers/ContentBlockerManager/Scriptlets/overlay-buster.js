// overlay-buster.js — MutationObserver removes fixed high-z-index viewport-covering overlays.
// Restores body scroll when overlays are removed.
// Usage: overlay-buster()
(function() {
    'use strict';
    function isOverlay(el) {
        if (!(el instanceof HTMLElement)) return false;
        const style = getComputedStyle(el);
        if (style.position !== 'fixed' && style.position !== 'absolute') return false;
        const zIndex = parseInt(style.zIndex, 10);
        if (isNaN(zIndex) || zIndex < 900) return false;
        const rect = el.getBoundingClientRect();
        const vw = window.innerWidth;
        const vh = window.innerHeight;
        if (rect.width < vw * 0.5 || rect.height < vh * 0.5) return false;
        const opacity = parseFloat(style.opacity);
        if (opacity === 0) return false;
        return true;
    }

    function restoreScroll() {
        const body = document.body;
        if (!body) return;
        const style = body.style;
        if (style.overflow === 'hidden') style.overflow = '';
        if (style.position === 'fixed') style.position = '';
        const html = document.documentElement;
        if (html.style.overflow === 'hidden') html.style.overflow = '';
    }

    function check() {
        const elements = document.querySelectorAll('div, section, aside');
        for (const el of elements) {
            if (isOverlay(el)) {
                el.remove();
                restoreScroll();
            }
        }
    }

    const observer = new MutationObserver(check);
    if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            observer.observe(document.body, { childList: true, subtree: true });
        });
    }
    // Also run periodically for dynamically injected overlays
    setTimeout(check, 2000);
    setTimeout(check, 5000);
})();
