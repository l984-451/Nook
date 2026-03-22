// trusted-json-edit-xhr-response.js — Edit XHR response JSON (set values, not just delete).
// Same XHR interception as json-prune-xhr-response but supports setting values.
// Usage: trusted-json-edit-xhr-response(editExpression, propsToMatch, [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const editExpression = args[0] || '';
    const propsToMatch = args[1] || '';
    const urlPattern = args[2] || '';

    if (!editExpression) return;

    let urlRe;
    if (urlPattern) {
        try { urlRe = new RegExp(urlPattern); } catch (e) {
            urlRe = { test: (s) => s.includes(urlPattern) };
        }
    }

    function parseValue(val) {
        if (val === 'true') return true;
        if (val === 'false') return false;
        if (val === 'null') return null;
        if (val === 'undefined') return undefined;
        if (val === '""' || val === "''") return '';
        const num = Number(val);
        if (!isNaN(num) && val !== '') return num;
        try { return JSON.parse(val); } catch (e) {}
        return val;
    }

    function parseEdits(expr) {
        const edits = [];
        const parts = expr.split(/\s*,\s*/);
        for (const part of parts) {
            const trimmed = part.trim();
            if (!trimmed) continue;
            if (trimmed.startsWith('delete ')) {
                edits.push({ op: 'delete', path: trimmed.substring(7).trim() });
            } else if (trimmed.startsWith('set ')) {
                const rest = trimmed.substring(4).trim();
                const spaceIdx = rest.indexOf(' ');
                if (spaceIdx > 0) {
                    edits.push({ op: 'set', path: rest.substring(0, spaceIdx), value: parseValue(rest.substring(spaceIdx + 1).trim()) });
                }
            } else {
                const colonIdx = trimmed.indexOf(':');
                const spaceIdx = trimmed.indexOf(' ');
                let path, value;
                if (colonIdx > 0 && (spaceIdx < 0 || colonIdx < spaceIdx)) {
                    path = trimmed.substring(0, colonIdx);
                    value = parseValue(trimmed.substring(colonIdx + 1));
                } else if (spaceIdx > 0) {
                    path = trimmed.substring(0, spaceIdx);
                    value = parseValue(trimmed.substring(spaceIdx + 1));
                } else {
                    edits.push({ op: 'delete', path: trimmed });
                    continue;
                }
                edits.push({ op: 'set', path: path, value: value });
            }
        }
        return edits;
    }

    function applyEdits(obj, edits) {
        if (typeof obj !== 'object' || obj === null) return obj;
        for (const edit of edits) {
            const pathParts = edit.path.split('.');
            let target = obj;
            for (let i = 0; i < pathParts.length - 1; i++) {
                if (target == null || typeof target !== 'object') break;
                const part = pathParts[i];
                if (part === '[-]' && Array.isArray(target)) {
                    const remaining = { op: edit.op, path: pathParts.slice(i + 1).join('.'), value: edit.value };
                    for (const item of target) {
                        applyEdits(item, [remaining]);
                    }
                    target = null;
                    break;
                }
                if (!(part in target)) {
                    if (edit.op === 'set') target[part] = {};
                    else break;
                }
                target = target[part];
            }
            if (target != null && typeof target === 'object') {
                const lastKey = pathParts[pathParts.length - 1];
                if (edit.op === 'delete') {
                    delete target[lastKey];
                } else {
                    target[lastKey] = edit.value;
                }
            }
        }
        return obj;
    }

    const edits = parseEdits(editExpression);

    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url) {
        this._nookEditRespUrl = String(url);
        return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function() {
        if (urlRe && !urlRe.test(this._nookEditRespUrl || '')) {
            return origSend.apply(this, arguments);
        }

        const xhr = this;
        const origOnReady = xhr.onreadystatechange;
        const origOnLoad = xhr.onload;

        function modifyResponse() {
            if (xhr.readyState === 4) {
                try {
                    let text = xhr.responseText;
                    let json = JSON.parse(text);

                    // Check propsToMatch
                    if (propsToMatch) {
                        const checks = propsToMatch.split(/\s+/);
                        let match = true;
                        for (const check of checks) {
                            const [path, val] = check.split(':');
                            let current = json;
                            for (const part of path.split('.')) {
                                if (current == null || typeof current !== 'object') { match = false; break; }
                                current = current[part];
                            }
                            if (!match) break;
                            if (val !== undefined && String(current) !== val) { match = false; break; }
                        }
                        if (!match) return;
                    }

                    json = applyEdits(json, edits);
                    const modified = JSON.stringify(json);
                    if (modified !== text) {
                        Object.defineProperty(xhr, 'responseText', { value: modified, writable: false, configurable: true });
                        Object.defineProperty(xhr, 'response', { value: modified, writable: false, configurable: true });
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
