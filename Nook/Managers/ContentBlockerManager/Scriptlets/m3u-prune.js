// m3u-prune.js — Prunes HLS ad segments from M3U8 manifests.
// Intercepts fetch and XHR responses; when content starts with #EXTM3U,
// removes lines matching the segment pattern.
// Usage: m3u-prune(segmentPattern, [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const segmentPattern = args[0] || '';
    const urlPattern = args[1] || '';

    if (!segmentPattern) return;

    let segmentRe;
    try { segmentRe = new RegExp(segmentPattern); } catch (e) {
        segmentRe = { test: (s) => s.includes(segmentPattern) };
    }

    let urlRe;
    if (urlPattern) {
        try { urlRe = new RegExp(urlPattern); } catch (e) {
            urlRe = { test: (s) => s.includes(urlPattern) };
        }
    }

    function pruneM3U(text) {
        if (!text || !text.trimStart().startsWith('#EXTM3U')) return text;
        const lines = text.split('\n');
        const result = [];
        let skipNext = false;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (skipNext) {
                skipNext = false;
                continue;
            }
            if (segmentRe.test(line)) {
                // If this is a tag line, also skip the URI line that follows
                if (line.startsWith('#')) {
                    skipNext = true;
                }
                continue;
            }
            result.push(line);
        }
        return result.join('\n');
    }

    function urlMatches(url) {
        if (!urlRe) return true;
        return urlRe.test(url);
    }

    // Intercept fetch
    const originalFetch = window.fetch;
    window.fetch = new Proxy(originalFetch, {
        apply(target, thisArg, argumentsList) {
            const input = argumentsList[0];
            let url = '';
            if (typeof input === 'string') url = input;
            else if (input instanceof Request) url = input.url;
            else if (input instanceof URL) url = input.href;

            if (!urlMatches(url)) {
                return Reflect.apply(target, thisArg, argumentsList);
            }

            return Reflect.apply(target, thisArg, argumentsList).then(response => {
                const ct = response.headers.get('content-type') || '';
                if (ct.includes('mpegurl') || ct.includes('x-mpegurl') || url.includes('.m3u8') || url.includes('.m3u')) {
                    const clone = response.clone();
                    return clone.text().then(text => {
                        const pruned = pruneM3U(text);
                        if (pruned !== text) {
                            const newHeaders = new Headers(response.headers);
                            newHeaders.delete('content-length');
                            return new Response(pruned, {
                                status: response.status,
                                statusText: response.statusText,
                                headers: newHeaders
                            });
                        }
                        return response;
                    });
                }
                return response;
            });
        }
    });

    // Intercept XHR
    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url) {
        this._nookM3uUrl = String(url);
        return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function() {
        const reqUrl = this._nookM3uUrl || '';
        if (!urlMatches(reqUrl)) {
            return origSend.apply(this, arguments);
        }
        if (!reqUrl.includes('.m3u8') && !reqUrl.includes('.m3u') && !reqUrl.includes('mpegurl')) {
            return origSend.apply(this, arguments);
        }

        const xhr = this;
        const origOnReady = xhr.onreadystatechange;
        const origOnLoad = xhr.onload;

        function modifyResponse() {
            if (xhr.readyState === 4) {
                try {
                    const text = xhr.responseText;
                    const pruned = pruneM3U(text);
                    if (pruned !== text) {
                        Object.defineProperty(xhr, 'responseText', { value: pruned, writable: false, configurable: true });
                        Object.defineProperty(xhr, 'response', { value: pruned, writable: false, configurable: true });
                    }
                } catch (e) {}
            }
        }

        if (origOnReady) {
            xhr.onreadystatechange = function() { modifyResponse(); return origOnReady.apply(this, arguments); };
        }
        if (origOnLoad) {
            xhr.onload = function() { modifyResponse(); return origOnLoad.apply(this, arguments); };
        }
        xhr.addEventListener('load', modifyResponse);
        return origSend.apply(this, arguments);
    };
})();
