// observer-click.js — MutationObserver that clicks elements matching a selector when they appear.
// For video ads: also seeks <video> to end when an ad container selector matches.
// Usage: observer-click(clickSelector [, adContainerSelector])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const clickSelector = args[0] || '';
    const adContainerSelector = args[1] || '';

    if (!clickSelector) return;

    function process() {
        // Click matching elements (skip buttons, dismiss buttons, etc.)
        const els = document.querySelectorAll(clickSelector);
        for (const el of els) {
            if (el.offsetParent !== null || el.offsetWidth > 0) {
                el.click();
            }
        }

        // If an ad container selector is provided, check if ad is playing and skip
        if (adContainerSelector) {
            const container = document.querySelector(adContainerSelector);
            if (container) {
                const video = container.querySelector('video');
                if (video && video.duration && isFinite(video.duration) && video.currentTime < video.duration) {
                    video.currentTime = video.duration;
                }
            }
        }
    }

    const observer = new MutationObserver(process);

    function start() {
        const target = document.body || document.documentElement;
        if (target) {
            observer.observe(target, { childList: true, subtree: true, attributes: true });
            process();
        }
    }

    if (document.body) {
        start();
    } else {
        document.addEventListener('DOMContentLoaded', start);
    }
})();
