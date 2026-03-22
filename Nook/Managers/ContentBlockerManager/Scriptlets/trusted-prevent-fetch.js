// trusted-prevent-fetch.js — Block fetch with custom response.
// Usage: trusted-prevent-fetch(urlPattern, [status], [body])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const urlPattern = args[0] || '';
    const status = parseInt(args[1], 10) || 200;
    const body = args[2] || '';
    if (!urlPattern) return;

    let urlRe;
    try { urlRe = new RegExp(urlPattern); } catch(e) { urlRe = { test: (s) => s.includes(urlPattern) }; }

    const originalFetch = window.fetch;
    window.fetch = new Proxy(originalFetch, {
        apply(target, thisArg, argumentsList) {
            const input = argumentsList[0];
            let url = '';
            if (typeof input === 'string') url = input;
            else if (input instanceof Request) url = input.url;
            else if (input instanceof URL) url = input.href;

            if (urlRe.test(url)) {
                return Promise.resolve(new Response(body, { status: status, statusText: 'OK' }));
            }
            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
