// prevent-innerHTML.js — Override innerHTML setter, block if content matches pattern.
// Usage: prevent-innerHTML(pattern)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const pattern = args[0] || '';
    if (!pattern) return;

    let patternRe;
    try { patternRe = new RegExp(pattern); } catch (e) {
        patternRe = { test: (s) => s.includes(pattern) };
    }

    const descriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'innerHTML');
    if (!descriptor || !descriptor.set) return;

    const originalSet = descriptor.set;
    Object.defineProperty(Element.prototype, 'innerHTML', {
        get: descriptor.get,
        set: function(value) {
            if (typeof value === 'string' && patternRe.test(value)) {
                return;
            }
            return originalSet.call(this, value);
        },
        configurable: true,
        enumerable: true
    });
})();
