// trusted-jsonl-edit-fetch-response.js — Edit JSONL (newline-delimited JSON) fetch responses.
// Usage: trusted-jsonl-edit-fetch-response(editExpression, propsToMatch, [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const editExpression = args[0] || '';
    const propsToMatch = args[1] || '';
    const urlPattern = args[2] || '';
    if (!editExpression) return;

    let urlRe;
    if (urlPattern) {
        try { urlRe = new RegExp(urlPattern); } catch (e) { urlRe = { test: (s) => s.includes(urlPattern) }; }
    }

    function parseValue(val) {
        if (val === 'true') return true; if (val === 'false') return false;
        if (val === 'null') return null; if (val === '""'||val === "''") return '';
        const n = Number(val); if (!isNaN(n)&&val!=='') return n;
        try { return JSON.parse(val); } catch(e) {} return val;
    }

    function parseEdits(expr) {
        const edits = [];
        for (const part of expr.split(/\s*,\s*/)) {
            const t = part.trim(); if (!t) continue;
            if (t.startsWith('delete ')) { edits.push({op:'delete',path:t.substring(7).trim()}); continue; }
            if (t.startsWith('set ')) { const r=t.substring(4).trim(); const s=r.indexOf(' '); if(s>0) edits.push({op:'set',path:r.substring(0,s),value:parseValue(r.substring(s+1).trim())}); continue; }
            const c=t.indexOf(':'); const s=t.indexOf(' ');
            if(c>0&&(s<0||c<s)) edits.push({op:'set',path:t.substring(0,c),value:parseValue(t.substring(c+1))});
            else if(s>0) edits.push({op:'set',path:t.substring(0,s),value:parseValue(t.substring(s+1))});
            else edits.push({op:'delete',path:t});
        }
        return edits;
    }

    function applyEdits(obj, edits) {
        if (typeof obj !== 'object' || obj === null) return obj;
        for (const edit of edits) {
            const pp=edit.path.split('.'); let t=obj;
            for(let i=0;i<pp.length-1;i++){if(t==null||typeof t!=='object')break;if(!(pp[i] in t)){if(edit.op==='set')t[pp[i]]={};else break;}t=t[pp[i]];}
            if(t!=null&&typeof t==='object'){const lk=pp[pp.length-1];if(edit.op==='delete')delete t[lk];else t[lk]=edit.value;}
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

            return Reflect.apply(target, thisArg, argumentsList).then(response => {
                const clone = response.clone();
                return clone.text().then(text => {
                    try {
                        const lines = text.split('\n');
                        let modified = false;
                        const result = lines.map(line => {
                            const trimmed = line.trim();
                            if (!trimmed) return line;
                            try {
                                let json = JSON.parse(trimmed);
                                json = applyEdits(json, edits);
                                modified = true;
                                return JSON.stringify(json);
                            } catch (e) { return line; }
                        });
                        if (modified) {
                            const newHeaders = new Headers(response.headers);
                            newHeaders.delete('content-length');
                            return new Response(result.join('\n'), { status: response.status, statusText: response.statusText, headers: newHeaders });
                        }
                    } catch (e) {}
                    return response;
                });
            });
        }
    });
})();
