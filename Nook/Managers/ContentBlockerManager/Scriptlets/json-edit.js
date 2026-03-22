// json-edit.js — Edit JSON.parse results with restricted values (non-trusted version).
// Usage: json-edit(editExpression, [propsToMatch])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const editExpression = args[0] || '';
    const propsToMatch = args[1] || '';
    if (!editExpression) return;

    function parseValue(val) {
        if (val === 'true') return true;
        if (val === 'false') return false;
        if (val === 'null') return null;
        if (val === '""' || val === "''") return '';
        if (val === '0') return 0;
        if (val === '1') return 1;
        const num = Number(val);
        if (!isNaN(num) && val !== '') return num;
        return val;
    }

    function parseEdits(expr) {
        const edits = [];
        for (const part of expr.split(/\s*,\s*/)) {
            const t = part.trim(); if (!t) continue;
            if (t.startsWith('delete ')) { edits.push({ op: 'delete', path: t.substring(7).trim() }); continue; }
            const c = t.indexOf(':'); const s = t.indexOf(' ');
            if (c > 0 && (s < 0 || c < s)) edits.push({ op: 'set', path: t.substring(0, c), value: parseValue(t.substring(c + 1)) });
            else if (s > 0) edits.push({ op: 'set', path: t.substring(0, s), value: parseValue(t.substring(s + 1)) });
            else edits.push({ op: 'delete', path: t });
        }
        return edits;
    }

    function applyEdits(obj, edits) {
        if (typeof obj !== 'object' || obj === null) return obj;
        for (const edit of edits) {
            const pp = edit.path.split('.'); let t = obj;
            for (let i = 0; i < pp.length - 1; i++) { if (t == null || typeof t !== 'object') break; if (!(pp[i] in t)) break; t = t[pp[i]]; }
            if (t != null && typeof t === 'object') { const lk = pp[pp.length - 1]; if (edit.op === 'delete') delete t[lk]; else t[lk] = edit.value; }
        }
        return obj;
    }

    const edits = parseEdits(editExpression);
    const originalParse = JSON.parse;
    JSON.parse = new Proxy(originalParse, {
        apply(target, thisArg, argumentsList) {
            const result = Reflect.apply(target, thisArg, argumentsList);
            try {
                if (propsToMatch) {
                    let match = true;
                    for (const check of propsToMatch.split(/\s+/)) {
                        const [p, v] = check.split(':'); let cur = result;
                        for (const pt of p.split('.')) { if (cur == null || typeof cur !== 'object') { match = false; break; } cur = cur[pt]; }
                        if (!match) break; if (v !== undefined && String(cur) !== v) { match = false; break; }
                    }
                    if (!match) return result;
                }
                return applyEdits(result, edits);
            } catch (e) {} return result;
        }
    });
})();
