// jsonl-edit-xhr-response.js — Edit XHR JSONL responses (non-trusted).
// Usage: jsonl-edit-xhr-response(editExpression, propsToMatch, [urlPattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const editExpression = args[0] || '';
    const urlPattern = args[2] || '';
    if (!editExpression) return;

    let urlRe;
    if (urlPattern) { try { urlRe = new RegExp(urlPattern); } catch(e) { urlRe = { test: (s) => s.includes(urlPattern) }; } }

    function parseValue(val) {
        if(val==='true')return true;if(val==='false')return false;if(val==='null')return null;
        if(val==='""'||val==="''")return '';if(val==='0')return 0;if(val==='1')return 1;
        const n=Number(val);if(!isNaN(n)&&val!=='')return n;return val;
    }
    function parseEdits(expr) {
        const edits=[];for(const part of expr.split(/\s*,\s*/)){const t=part.trim();if(!t)continue;
        if(t.startsWith('delete ')){edits.push({op:'delete',path:t.substring(7).trim()});continue;}
        const c=t.indexOf(':');const s=t.indexOf(' ');
        if(c>0&&(s<0||c<s))edits.push({op:'set',path:t.substring(0,c),value:parseValue(t.substring(c+1))});
        else if(s>0)edits.push({op:'set',path:t.substring(0,s),value:parseValue(t.substring(s+1))});
        else edits.push({op:'delete',path:t});}return edits;
    }
    function applyEdits(obj, edits) {
        if(typeof obj!=='object'||obj===null)return obj;
        for(const edit of edits){const pp=edit.path.split('.');let t=obj;
        for(let i=0;i<pp.length-1;i++){if(t==null||typeof t!=='object')break;if(!(pp[i] in t))break;t=t[pp[i]];}
        if(t!=null&&typeof t==='object'){const lk=pp[pp.length-1];if(edit.op==='delete')delete t[lk];else t[lk]=edit.value;}}return obj;
    }

    const edits = parseEdits(editExpression);
    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) { this._nookJLUrl = String(url); return origOpen.apply(this, arguments); };
    XMLHttpRequest.prototype.send = function() {
        if (urlRe && !urlRe.test(this._nookJLUrl || '')) return origSend.apply(this, arguments);
        const xhr = this; const origOnReady = xhr.onreadystatechange; const origOnLoad = xhr.onload;
        function modifyResponse() { if (xhr.readyState === 4) { try {
            const text = xhr.responseText; const lines = text.split('\n'); let modified = false;
            const result = lines.map(line => { const trimmed = line.trim(); if (!trimmed) return line;
                try { let json = JSON.parse(trimmed); json = applyEdits(json, edits); modified = true; return JSON.stringify(json); } catch(e) { return line; }
            });
            if (modified) { const newText = result.join('\n');
                Object.defineProperty(xhr, 'responseText', { value: newText, writable: false, configurable: true });
                Object.defineProperty(xhr, 'response', { value: newText, writable: false, configurable: true }); }
        } catch(e) {} } }
        if(origOnReady){xhr.onreadystatechange=function(){modifyResponse();return origOnReady.apply(this,arguments);};}
        if(origOnLoad){xhr.onload=function(){modifyResponse();return origOnLoad.apply(this,arguments);};}
        xhr.addEventListener('load', modifyResponse);
        return origSend.apply(this, arguments);
    };
})();
