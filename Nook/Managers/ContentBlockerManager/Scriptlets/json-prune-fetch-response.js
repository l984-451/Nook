// json-prune-fetch-response.js — Intercepts fetch responses and prunes JSON keys.
// Usage: json-prune-fetch-response(keyPaths, [stack], [propsToMatch], [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const rawKeys = (args[0] || '').split(/\s+/);
    // args can have named params: propsToMatch, url:pattern
    let urlPattern = '';
    for (let i = 1; i < args.length; i++) {
        if (args[i] && args[i].startsWith('url:')) {
            urlPattern = args[i].substring(4);
        }
    }

    let urlRe;
    if (urlPattern) {
        try { urlRe = new RegExp(urlPattern); } catch (e) {
            urlRe = { test: (s) => s.includes(urlPattern) };
        }
    }

    const pruneKeys = rawKeys.map(k => k.split('.'));

    function pruneObject(obj) {
        if (typeof obj !== 'object' || obj === null) return obj;
        for (const keyPath of pruneKeys) {
            let current = obj;
            for (let i = 0; i < keyPath.length - 1; i++) {
                const part = keyPath[i];
                if (part === '[-]' && Array.isArray(current)) {
                    // Wildcard array — prune from all elements
                    const remaining = keyPath.slice(i + 1);
                    for (const item of current) {
                        pruneObject(item);
                    }
                    break;
                }
                if (current == null || typeof current !== 'object') break;
                current = current[part];
            }
            if (current != null && typeof current === 'object') {
                const lastKey = keyPath[keyPath.length - 1];
                if (lastKey in current) {
                    delete current[lastKey];
                }
            }
        }
        return obj;
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
                    try {
                        let json = JSON.parse(text);
                        json = pruneObject(json);
                        const newHeaders = new Headers(response.headers);
                        newHeaders.delete('content-length');
                        return new Response(JSON.stringify(json), {
                            status: response.status,
                            statusText: response.statusText,
                            headers: newHeaders
                        });
                    } catch (e) {
                        return response;
                    }
                });
            });
        }
    });
})();
