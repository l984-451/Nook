// trusted-replace-fetch-response.js — Replaces text in fetch responses.
// Usage: trusted-replace-fetch-response(pattern, replacement, [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const pattern = args[0] || '';
    const replacement = args[1] || '';
    const urlMatch = args[2] || '';

    if (!pattern) return;

    let patternRe;
    try { patternRe = new RegExp(pattern, 'g'); } catch (e) {
        patternRe = null;
    }

    let urlRe;
    if (urlMatch) {
        try { urlRe = new RegExp(urlMatch); } catch (e) {
            urlRe = { test: (s) => s.includes(urlMatch) };
        }
    }

    const originalFetch = window.fetch;
    window.fetch = new Proxy(originalFetch, {
        apply(target, thisArg, argumentsList) {
            const input = argumentsList[0];
            let url = '';
            if (typeof input === 'string') url = input;
            else if (input instanceof Request) url = input.url;
            else if (input instanceof URL) url = input.href;

            if (urlRe && !urlRe.test(url)) {
                return Reflect.apply(target, thisArg, argumentsList);
            }

            return Reflect.apply(target, thisArg, argumentsList).then(response => {
                const clone = response.clone();
                return clone.text().then(text => {
                    let modified = text;
                    if (patternRe) {
                        modified = text.replace(patternRe, replacement);
                    } else {
                        modified = text.split(pattern).join(replacement);
                    }
                    if (modified !== text) {
                        return new Response(modified, {
                            status: response.status,
                            statusText: response.statusText,
                            headers: response.headers
                        });
                    }
                    return response;
                });
            });
        }
    });
})();
