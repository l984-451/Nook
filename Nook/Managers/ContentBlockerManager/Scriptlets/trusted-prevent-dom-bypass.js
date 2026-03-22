// trusted-prevent-dom-bypass.js — Block DOM-based ad re-injection.
// Intercepts appendChild, insertBefore, append; blocks script elements matching pattern.
// Usage: trusted-prevent-dom-bypass(methodPath, contentPattern)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const methodPath = args[0] || '';
    const contentPattern = args[1] || '';

    if (!contentPattern) return;

    let contentRe;
    try { contentRe = new RegExp(contentPattern); } catch (e) {
        contentRe = { test: (s) => s.includes(contentPattern) };
    }

    function shouldBlock(node) {
        if (!node || !(node instanceof HTMLElement)) return false;
        // Check script elements
        if (node.tagName === 'SCRIPT') {
            const src = node.src || '';
            const text = node.textContent || '';
            if (contentRe.test(src) || contentRe.test(text)) return true;
        }
        // Check iframes
        if (node.tagName === 'IFRAME') {
            const src = node.src || '';
            if (contentRe.test(src)) return true;
        }
        // Check innerHTML/outerHTML for generic elements
        try {
            const html = node.outerHTML || '';
            if (html.length < 10000 && contentRe.test(html)) return true;
        } catch (e) {}
        return false;
    }

    // Determine which methods to intercept
    const methods = methodPath ? methodPath.split(/\s+/) : ['appendChild', 'insertBefore', 'append', 'prepend', 'after', 'before'];

    for (const method of methods) {
        const parts = method.split('.');
        let target, methodName;

        if (parts.length >= 2) {
            // e.g. "Node.prototype.appendChild"
            try {
                target = window;
                for (let i = 0; i < parts.length - 1; i++) {
                    target = target[parts[i]];
                }
                methodName = parts[parts.length - 1];
            } catch (e) { continue; }
        } else {
            // Short form — default to Node.prototype or Element.prototype
            methodName = parts[0];
            if (['appendChild', 'insertBefore', 'removeChild', 'replaceChild'].includes(methodName)) {
                target = Node.prototype;
            } else {
                target = Element.prototype;
            }
        }

        if (!target || typeof target[methodName] !== 'function') continue;

        const original = target[methodName];
        target[methodName] = function() {
            for (let i = 0; i < arguments.length; i++) {
                const arg = arguments[i];
                if (arg instanceof Node && shouldBlock(arg)) {
                    // Return the node without appending (mimics successful append)
                    return arg;
                }
            }
            return original.apply(this, arguments);
        };
    }
})();
