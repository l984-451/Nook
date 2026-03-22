// abort-current-script.js (acs) — Aborts script execution when a specific
// property is accessed and the call stack matches an optional pattern.
// Usage: abort-current-script(property, [search])
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const prop = args[0] || '';
    const search = args[1] || '';

    if (!prop) return;

    const chain = prop.split('.');
    let owner = window;

    for (let i = 0; i < chain.length - 1; i++) {
        if (!(chain[i] in owner)) return;
        owner = owner[chain[i]];
        if (owner == null) return;
    }

    const target = chain[chain.length - 1];
    const descriptor = Object.getOwnPropertyDescriptor(owner, target);
    const original = descriptor && descriptor.value ? descriptor.value : owner[target];

    let searchRe;
    if (search) {
        try { searchRe = new RegExp(search); } catch (e) {
            searchRe = { test: (s) => s.includes(search) };
        }
    }

    if (typeof original === 'function') {
        owner[target] = new Proxy(original, {
            apply(target, thisArg, argumentsList) {
                if (searchRe) {
                    const stack = new Error().stack || '';
                    if (searchRe.test(stack)) {
                        throw new ReferenceError('Nook: abort-current-script');
                    }
                } else {
                    throw new ReferenceError('Nook: abort-current-script');
                }
                return Reflect.apply(target, thisArg, argumentsList);
            }
        });
    } else {
        const trap = {
            get(target, key) {
                if (key === target) {
                    if (searchRe) {
                        const stack = new Error().stack || '';
                        if (searchRe.test(stack)) {
                            throw new ReferenceError('Nook: abort-current-script');
                        }
                    } else {
                        throw new ReferenceError('Nook: abort-current-script');
                    }
                }
                return original;
            },
            set(_, __, val) { return true; }
        };
        try {
            Object.defineProperty(owner, target, {
                get() {
                    if (searchRe) {
                        const stack = new Error().stack || '';
                        if (searchRe.test(stack)) {
                            throw new ReferenceError('Nook: abort-current-script');
                        }
                    } else {
                        throw new ReferenceError('Nook: abort-current-script');
                    }
                    return original;
                },
                set(val) {},
                configurable: true
            });
        } catch (e) {}
    }
})();
