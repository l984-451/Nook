// no-fetch-if.js — Wraps fetch() to block requests matching specified patterns.
// YouTube: blocks googlevideo.com/initplayback ad calls.
// Usage: no-fetch-if(urlPattern [, propsToMatch])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const urlPattern = args[0] || '';
    const propsToMatch = args[1] || '';

    let urlRe;
    try { urlRe = new RegExp(urlPattern); } catch (e) {
        urlRe = { test: (s) => s.includes(urlPattern) };
    }

    const originalFetch = window.fetch;

    window.fetch = new Proxy(originalFetch, {
        apply(target, thisArg, argumentsList) {
            const input = argumentsList[0];
            let url = '';
            if (typeof input === 'string') {
                url = input;
            } else if (input instanceof Request) {
                url = input.url;
            } else if (input instanceof URL) {
                url = input.href;
            }

            if (urlRe.test(url)) {
                // Check additional props if specified
                if (propsToMatch) {
                    const opts = argumentsList[1] || {};
                    const checks = propsToMatch.split(/\s+/);
                    let match = true;
                    for (const check of checks) {
                        const [prop, val] = check.split(':');
                        if (val !== undefined && String(opts[prop]) !== val) {
                            match = false;
                            break;
                        }
                    }
                    if (!match) {
                        return Reflect.apply(target, thisArg, argumentsList);
                    }
                }
                return Promise.resolve(new Response('{}', { status: 200, statusText: 'OK' }));
            }
            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
