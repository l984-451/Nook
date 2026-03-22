// fingerprint2.js — Neutralizes Fingerprint2 library.
// Usage: fingerprint2()
(function() {
    'use strict';
    const Fingerprint2 = function() {};
    Fingerprint2.prototype = {
        get: function(opts, cb) {
            if (typeof opts === 'function') { cb = opts; }
            if (typeof cb === 'function') {
                setTimeout(() => cb('0', []), 1);
            }
        },
        key: 'fingerprint2-noop'
    };
    Fingerprint2.get = function(opts, cb) {
        if (typeof opts === 'function') { cb = opts; }
        if (typeof cb === 'function') {
            setTimeout(() => cb([{ key: 'noop', value: '0' }]), 1);
        }
    };
    Fingerprint2.getPromise = function() {
        return Promise.resolve([{ key: 'noop', value: '0' }]);
    };
    window.Fingerprint2 = Fingerprint2;
})();
