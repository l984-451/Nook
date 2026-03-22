// addEventListener-defuser.js (aeld) — Prevents addEventListener calls matching patterns.
// Usage: addEventListener-defuser(type, [pattern])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const type = args[0] || '';
    const needle = args[1] || '';

    let needleRe;
    if (needle) {
        try { needleRe = new RegExp(needle); } catch (e) {
            needleRe = { test: (s) => s.includes(needle) };
        }
    }

    const origAdd = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = new Proxy(origAdd, {
        apply(target, thisArg, argumentsList) {
            const evtType = String(argumentsList[0] || '');
            if (type && evtType !== type && type !== '*') {
                return Reflect.apply(target, thisArg, argumentsList);
            }
            if (needleRe) {
                const handler = argumentsList[1];
                const handlerStr = typeof handler === 'function' ? handler.toString() : String(handler);
                if (needleRe.test(handlerStr)) {
                    return; // Block this listener
                }
            } else if (type) {
                return; // Block all listeners of this type
            }
            return Reflect.apply(target, thisArg, argumentsList);
        }
    });
})();
