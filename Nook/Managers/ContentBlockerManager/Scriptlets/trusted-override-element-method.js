// trusted-override-element-method.js — Override a method on Element prototype.
// Usage: trusted-override-element-method(elementType, methodName, behavior)
(function() {
    'use strict';
    const args = JSON.parse('{{ARGS}}');
    const elementType = args[0] || 'Element';
    const methodName = args[1] || '';
    const behavior = args[2] || 'noop';
    if (!methodName) return;

    let proto;
    try { proto = window[elementType] && window[elementType].prototype; } catch(e) { return; }
    if (!proto || typeof proto[methodName] !== 'function') return;

    const original = proto[methodName];
    if (behavior === 'noop') {
        proto[methodName] = function() { return undefined; };
    } else if (behavior === 'true') {
        proto[methodName] = function() { return true; };
    } else if (behavior === 'false') {
        proto[methodName] = function() { return false; };
    } else if (behavior === 'null') {
        proto[methodName] = function() { return null; };
    } else if (behavior === 'throw') {
        proto[methodName] = function() { throw new Error('Blocked'); };
    } else {
        proto[methodName] = function() { return original.apply(this, arguments); };
    }
})();
