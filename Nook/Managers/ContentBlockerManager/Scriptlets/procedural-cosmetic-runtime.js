// procedural-cosmetic-runtime.js — Runtime for procedural cosmetic filter operators.
// Accepts {{RULES}} as JSON array, uses MutationObserver for live updates.
(function() {
    'use strict';
    const rules = JSON.parse('{{RULES}}');
    if (!rules || rules.length === 0) return;

    function applyOp(elements, op) {
        const result = [];
        for (const el of elements) {
            try {
                switch (op.type) {
                    case 'has-text': {
                        let re;
                        try { re = new RegExp(op.arg); } catch(e) { re = { test: s => s.includes(op.arg) }; }
                        if (re.test(el.textContent || '')) {
                            el.style.setProperty('display', 'none', 'important');
                            result.push(el);
                        }
                        break;
                    }
                    case 'xpath': {
                        const xr = document.evaluate(op.arg, el, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
                        for (let i = 0; i < xr.snapshotLength; i++) {
                            const n = xr.snapshotItem(i);
                            if (n instanceof HTMLElement) {
                                n.style.setProperty('display', 'none', 'important');
                                result.push(n);
                            }
                        }
                        continue;
                    }
                    case 'style': {
                        const decls = op.arg.split(';');
                        for (const d of decls) {
                            const parts = d.split(':');
                            if (parts.length >= 2) {
                                const prop = parts[0].trim();
                                const val = parts.slice(1).join(':').trim();
                                if (prop && val) el.style.setProperty(prop, val, 'important');
                            }
                        }
                        result.push(el);
                        break;
                    }
                    case 'matches-css': {
                        const [prop, val] = op.arg.split(':').map(s => s.trim());
                        const computed = getComputedStyle(el)[prop];
                        let valRe;
                        try { valRe = new RegExp(val); } catch(e) { valRe = { test: s => s === val }; }
                        if (valRe.test(computed)) {
                            el.style.setProperty('display', 'none', 'important');
                            result.push(el);
                        }
                        break;
                    }
                    case 'matches-css-before': {
                        const [prop, val] = op.arg.split(':').map(s => s.trim());
                        const computed = getComputedStyle(el, '::before')[prop];
                        let valRe;
                        try { valRe = new RegExp(val); } catch(e) { valRe = { test: s => s === val }; }
                        if (valRe.test(computed)) {
                            el.style.setProperty('display', 'none', 'important');
                            result.push(el);
                        }
                        break;
                    }
                    case 'matches-css-after': {
                        const [prop, val] = op.arg.split(':').map(s => s.trim());
                        const computed = getComputedStyle(el, '::after')[prop];
                        let valRe;
                        try { valRe = new RegExp(val); } catch(e) { valRe = { test: s => s === val }; }
                        if (valRe.test(computed)) {
                            el.style.setProperty('display', 'none', 'important');
                            result.push(el);
                        }
                        break;
                    }
                    case 'upward': {
                        const n = parseInt(op.arg, 10);
                        let target = el;
                        if (!isNaN(n)) {
                            for (let i = 0; i < n && target; i++) target = target.parentElement;
                        } else {
                            target = el.closest(op.arg);
                        }
                        if (target) {
                            target.style.setProperty('display', 'none', 'important');
                            result.push(target);
                        }
                        continue;
                    }
                    case 'remove': {
                        el.remove();
                        continue;
                    }
                    case 'remove-attr': {
                        const attrs = op.arg.split(/\s*\|\s*/);
                        for (const attr of attrs) {
                            let attrRe;
                            try { attrRe = new RegExp(attr); } catch(e) { attrRe = null; }
                            if (attrRe) {
                                for (const a of Array.from(el.attributes)) {
                                    if (attrRe.test(a.name)) el.removeAttribute(a.name);
                                }
                            } else {
                                el.removeAttribute(attr);
                            }
                        }
                        result.push(el);
                        break;
                    }
                    case 'remove-class': {
                        const classes = op.arg.split(/\s*\|\s*/);
                        for (const cls of classes) {
                            let clsRe;
                            try { clsRe = new RegExp(cls); } catch(e) { clsRe = null; }
                            if (clsRe) {
                                for (const c of Array.from(el.classList)) {
                                    if (clsRe.test(c)) el.classList.remove(c);
                                }
                            } else {
                                el.classList.remove(cls);
                            }
                        }
                        result.push(el);
                        break;
                    }
                    case 'others': {
                        const parent = el.parentElement;
                        if (parent) {
                            for (const sibling of parent.children) {
                                if (sibling !== el) sibling.style.setProperty('display', 'none', 'important');
                            }
                        }
                        result.push(el);
                        break;
                    }
                    case 'min-text-length': {
                        if ((el.textContent || '').length >= parseInt(op.arg, 10)) {
                            el.style.setProperty('display', 'none', 'important');
                            result.push(el);
                        }
                        break;
                    }
                    case 'matches-attr': {
                        const eqIdx = op.arg.indexOf('=');
                        const attr = eqIdx > 0 ? op.arg.substring(0, eqIdx) : op.arg;
                        const val = eqIdx > 0 ? op.arg.substring(eqIdx + 1) : null;
                        const attrVal = el.getAttribute(attr);
                        if (attrVal !== null) {
                            if (!val || attrVal === val) {
                                el.style.setProperty('display', 'none', 'important');
                                result.push(el);
                            } else {
                                try {
                                    if (new RegExp(val).test(attrVal)) {
                                        el.style.setProperty('display', 'none', 'important');
                                        result.push(el);
                                    }
                                } catch(e) {}
                            }
                        }
                        break;
                    }
                    case 'matches-path': {
                        let re;
                        try { re = new RegExp(op.arg); } catch(e) { re = { test: s => s.includes(op.arg) }; }
                        if (re.test(location.pathname)) {
                            el.style.setProperty('display', 'none', 'important');
                            result.push(el);
                        }
                        break;
                    }
                    case 'matches-prop': {
                        const eqIdx = op.arg.indexOf('=');
                        const propPath = eqIdx > 0 ? op.arg.substring(0, eqIdx) : op.arg;
                        const propVal = eqIdx > 0 ? op.arg.substring(eqIdx + 1) : null;
                        let current = el;
                        for (const part of propPath.split('.')) {
                            if (current == null) break;
                            current = current[part];
                        }
                        if (current !== undefined) {
                            if (!propVal || String(current) === propVal) {
                                el.style.setProperty('display', 'none', 'important');
                                result.push(el);
                            }
                        }
                        break;
                    }
                    case 'watch-attr': {
                        const attrs = op.arg ? op.arg.split(/\s*\|\s*/) : undefined;
                        const attrObserver = new MutationObserver(() => processRules());
                        attrObserver.observe(el, { attributes: true, attributeFilter: attrs });
                        result.push(el);
                        break;
                    }
                    case 'not': {
                        // :not(selector) — keep elements that DON'T match
                        try {
                            if (!el.matches(op.arg)) {
                                result.push(el);
                            }
                        } catch(e) { result.push(el); }
                        break;
                    }
                    default:
                        result.push(el);
                        break;
                }
            } catch(e) {}
        }
        return result;
    }

    function processRules() {
        for (const rule of rules) {
            try {
                let elements;
                if (rule.selector === '*') {
                    elements = [document.documentElement];
                } else {
                    elements = Array.from(document.querySelectorAll(rule.selector));
                }
                for (const op of rule.operations) {
                    elements = applyOp(elements, op);
                }
            } catch(e) {}
        }
    }

    processRules();

    const observer = new MutationObserver(function() {
        processRules();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
})();
