// trusted-json-edit.js — Edit JSON.parse results (set values, not just delete).
// Usage: trusted-json-edit(editExpression, [propsToMatch])
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
                if (colonIdx > 0 && (spaceIdx < 0 || colonIdx < spaceIdx)) {
                    edits.push({ op: 'set', path: trimmed.substring(0, colonIdx), value: parseValue(trimmed.substring(colonIdx + 1)) });
                } else if (spaceIdx > 0) {
                    edits.push({ op: 'set', path: trimmed.substring(0, spaceIdx), value: parseValue(trimmed.substring(spaceIdx + 1)) });
                } else {
                    edits.push({ op: 'delete', path: trimmed });
                }
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
                if (!(pathParts[i] in target)) {
                    if (edit.op === 'set') target[pathParts[i]] = {};
                    else break;
                }
                target = target[pathParts[i]];
            }
            if (target != null && typeof target === 'object') {
                const lastKey = pathParts[pathParts.length - 1];
                if (edit.op === 'delete') delete target[lastKey];
                else target[lastKey] = edit.value;
            }
        }
        return obj;
    }

    function shouldApply(obj) {
        if (!propsToMatch) return true;
        const checks = propsToMatch.split(/\s+/);
        for (const check of checks) {
            const [path, val] = check.split(':');
            let current = obj;
            for (const part of path.split('.')) {
                if (current == null || typeof current !== 'object') return false;
                if (!(part in current)) return false;
                current = current[part];
            }
            if (val !== undefined && String(current) !== val) return false;
        }
        return true;
    }

    const edits = parseEdits(editExpression);
    const originalParse = JSON.parse;
    JSON.parse = new Proxy(originalParse, {
        apply(target, thisArg, argumentsList) {
            const result = Reflect.apply(target, thisArg, argumentsList);
            try {
                if (shouldApply(result)) return applyEdits(result, edits);
            } catch (e) {}
            return result;
        }
    });
})();
