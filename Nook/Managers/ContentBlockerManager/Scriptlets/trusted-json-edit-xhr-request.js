// trusted-json-edit-xhr-request.js — Edit outgoing XHR request bodies.
// Intercepts XMLHttpRequest.prototype.send, parses body as JSON, applies edits.
// Usage: trusted-json-edit-xhr-request(editExpression, propsToMatch, [urlPattern])
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

    function parseEdits(expr) {
        // Format: "key1.path value1, key2.path value2" or "key1.path:value1 key2.path:value2"
        // Also supports: "set key value", "delete key"
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
                // "path:value" or "path value" format
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

    function applyEdits(obj, edits) {
        if (typeof obj !== 'object' || obj === null) return obj;
        for (const edit of edits) {
            const pathParts = edit.path.split('.');
            let target = obj;
            for (let i = 0; i < pathParts.length - 1; i++) {
                if (target == null || typeof target !== 'object') break;
                if (!(pathParts[i] in target)) {
                    if (edit.op === 'set') target[pathParts[i]] = {};
                    else break;
                }
                target = target[pathParts[i]];
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
        this._nookEditUrl = String(url);
        return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function(body) {
        if (urlRe && !urlRe.test(this._nookEditUrl || '')) {
            return origSend.apply(this, arguments);
        }

        if (body && typeof body === 'string') {
            try {
                let json = JSON.parse(body);

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
                    if (!match) return origSend.apply(this, arguments);
                }

                json = applyEdits(json, edits);
                return origSend.call(this, JSON.stringify(json));
            } catch (e) {}
        }
        return origSend.apply(this, arguments);
    };
})();
