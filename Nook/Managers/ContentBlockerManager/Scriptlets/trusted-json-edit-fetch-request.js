// trusted-json-edit-fetch-request.js — Edit outgoing fetch request bodies.
// Usage: trusted-json-edit-fetch-request(editExpression, propsToMatch, [urlPattern])
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
        if (val === '""' || val === "''") return '';
        const num = Number(val);
        if (!isNaN(num) && val !== '') return num;
        try { return JSON.parse(val); } catch (e) {}
        return val;
    }

    function parseEdits(expr) {
        const edits = [];
        for (const part of expr.split(/\s*,\s*/)) {
            const t = part.trim();
            if (!t) continue;
            if (t.startsWith('delete ')) { edits.push({ op: 'delete', path: t.substring(7).trim() }); continue; }
            if (t.startsWith('set ')) { const r = t.substring(4).trim(); const s = r.indexOf(' '); if (s > 0) edits.push({ op: 'set', path: r.substring(0, s), value: parseValue(r.substring(s+1).trim()) }); continue; }
            const c = t.indexOf(':'); const s = t.indexOf(' ');
            if (c > 0 && (s < 0 || c < s)) edits.push({ op: 'set', path: t.substring(0, c), value: parseValue(t.substring(c+1)) });
            else if (s > 0) edits.push({ op: 'set', path: t.substring(0, s), value: parseValue(t.substring(s+1)) });
            else edits.push({ op: 'delete', path: t });
        }
        return edits;
    }

    function applyEdits(obj, edits) {
        if (typeof obj !== 'object' || obj === null) return obj;
        for (const edit of edits) {
            const pp = edit.path.split('.'); let t = obj;
            for (let i = 0; i < pp.length - 1; i++) { if (t == null || typeof t !== 'object') break; if (!(pp[i] in t)) { if (edit.op==='set') t[pp[i]]={}; else break; } t = t[pp[i]]; }
            if (t != null && typeof t === 'object') { const lk = pp[pp.length-1]; if (edit.op==='delete') delete t[lk]; else t[lk] = edit.value; }
        }
        return obj;
    }

    const edits = parseEdits(editExpression);
    const originalFetch = window.fetch;
    window.fetch = new Proxy(originalFetch, {
        apply(target, thisArg, argumentsList) {
            const input = argumentsList[0];
            let url = '';
            if (typeof input === 'string') url = input;
            else if (input instanceof Request) url = input.url;
            else if (input instanceof URL) url = input.href;

            if (urlRe && !urlRe.test(url)) return Reflect.apply(target, thisArg, argumentsList);

            const opts = argumentsList[1] || {};
            if (opts.body && typeof opts.body === 'string') {
                try {
                    let json = JSON.parse(opts.body);
                    if (propsToMatch) {
                        let match = true;
                        for (const check of propsToMatch.split(/\s+/)) {
                            const [p, v] = check.split(':'); let cur = json;
                            for (const pt of p.split('.')) { if (cur==null||typeof cur!=='object') { match=false; break; } cur=cur[pt]; }
                            if (!match) break; if (v !== undefined && String(cur) !== v) { match=false; break; }
                        }
                        if (!match) return Reflect.apply(target, thisArg, argumentsList);
                    }
                    json = applyEdits(json, edits);
                    const newOpts = Object.assign({}, opts, { body: JSON.stringify(json) });
                    return Reflect.apply(target, thisArg, [input, newOpts]);
                } catch (e) {}
            }
            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
